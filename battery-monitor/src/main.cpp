#include <libudev.h>

#include <algorithm>
#include <cerrno>
#include <csignal>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <optional>
#include <poll.h>
#include <string>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
#include <utility>
#include <vector>

namespace fs = std::filesystem;

namespace {

volatile std::sig_atomic_t running = 1;

void handleSignal(int) {
    running = 0;
}

fs::path powerSupplyPath() {
    const char* overridePath = std::getenv("NEO_BATTERY_SYSFS_PATH");
    return overridePath != nullptr && *overridePath != '\0'
        ? fs::path(overridePath)
        : fs::path("/sys/class/power_supply");
}

std::string trim(std::string value) {
    const auto first = value.find_first_not_of(" \t\r\n");
    if (first == std::string::npos) {
        return {};
    }
    const auto last = value.find_last_not_of(" \t\r\n");
    return value.substr(first, last - first + 1);
}

std::optional<std::string> readText(const fs::path& filePath) {
    std::ifstream file(filePath);
    if (!file) {
        return std::nullopt;
    }
    std::string value;
    if (!std::getline(file, value)) {
        return std::nullopt;
    }
    return trim(std::move(value));
}

std::optional<long long> readInteger(const fs::path& filePath) {
    const auto value = readText(filePath);
    if (!value || value->empty()) {
        return std::nullopt;
    }
    try {
        std::size_t parsed = 0;
        const long long result = std::stoll(*value, &parsed, 10);
        if (parsed != value->size()) {
            return std::nullopt;
        }
        return result;
    } catch (...) {
        return std::nullopt;
    }
}

struct Snapshot {
    std::string batteryName;
    std::string batteryStatus = "Unknown";
    std::optional<int> capacity;
    std::optional<bool> externalPowerOnline;
    std::optional<long long> voltageNow;
    std::optional<long long> currentNow;
    std::optional<long long> energyNow;
    std::optional<long long> energyFull;
    std::optional<long long> chargeNow;
    std::optional<long long> chargeFull;
};

bool isExternalPowerType(const std::string& type) {
    return type == "Mains" || type == "USB" || type == "USB_C" ||
           type == "USB_PD" || type == "Wireless";
}

Snapshot readSnapshot() {
    Snapshot snapshot;
    std::error_code error;
    std::vector<fs::path> devices;

    fs::directory_iterator iterator(powerSupplyPath(), error);
    if (error) {
        return snapshot;
    }

    const fs::directory_iterator end;
    for (; iterator != end; iterator.increment(error)) {
        if (error) {
            break;
        }
        devices.push_back(iterator->path());
    }
    std::sort(devices.begin(), devices.end());

    bool sawExternalPower = false;
    bool externalPowerOnline = false;
    for (const auto& device : devices) {
        const auto type = readText(device / "type");
        if (!type) {
            continue;
        }

        if (*type == "Battery" && snapshot.batteryName.empty()) {
            snapshot.batteryName = device.filename().string();
            if (const auto value = readInteger(device / "capacity")) {
                snapshot.capacity = static_cast<int>(
                    std::clamp(*value, 0LL, 100LL));
            }
            if (const auto value = readText(device / "status")) {
                snapshot.batteryStatus = *value;
            }
            snapshot.voltageNow = readInteger(device / "voltage_now");
            snapshot.currentNow = readInteger(device / "current_now");
            snapshot.energyNow = readInteger(device / "energy_now");
            snapshot.energyFull = readInteger(device / "energy_full");
            snapshot.chargeNow = readInteger(device / "charge_now");
            snapshot.chargeFull = readInteger(device / "charge_full");
            continue;
        }

        if (isExternalPowerType(*type)) {
            const auto online = readInteger(device / "online");
            if (online) {
                sawExternalPower = true;
                externalPowerOnline = externalPowerOnline || *online == 1;
            }
        }
    }

    if (sawExternalPower) {
        snapshot.externalPowerOnline = externalPowerOnline;
    }
    return snapshot;
}

std::string powerLabel(const Snapshot& snapshot) {
    if (!snapshot.externalPowerOnline) {
        return "Power unknown";
    }
    return *snapshot.externalPowerOnline ? "AC connected" : "On battery";
}

std::string statusText(const Snapshot& snapshot) {
    if (snapshot.batteryName.empty()) {
        return "Battery unavailable";
    }
    std::string text = "BAT ";
    text += snapshot.capacity ? std::to_string(*snapshot.capacity) + "%" : "--%";
    if (!snapshot.batteryStatus.empty() && snapshot.batteryStatus != "Unknown") {
        text += " | " + snapshot.batteryStatus;
    }
    text += " | " + powerLabel(snapshot);
    return text;
}

const char* statusColor(const Snapshot& snapshot) {
    if (snapshot.capacity && *snapshot.capacity <= 15) {
        return "#e06c75";
    }
    if (snapshot.externalPowerOnline && *snapshot.externalPowerOnline) {
        return "#98c379";
    }
    return "#e5c07b";
}

void printStatus() {
    const Snapshot snapshot = readSnapshot();
    std::cout << "<span color='" << statusColor(snapshot) << "'>"
              << statusText(snapshot) << "</span>\n";
}

void printCheck() {
    const Snapshot snapshot = readSnapshot();
    std::cout << "NEO Battery Monitor hardware check\n"
              << "Battery device: "
              << (snapshot.batteryName.empty() ? "Not found" : snapshot.batteryName)
              << "\nCapacity: ";
    if (snapshot.capacity) {
        std::cout << *snapshot.capacity << "%\n";
    } else {
        std::cout << "Not reported\n";
    }
    std::cout << "Battery status: " << snapshot.batteryStatus << '\n'
              << "External power: " << powerLabel(snapshot) << '\n';
    if (snapshot.voltageNow) {
        std::cout << "Voltage: " << *snapshot.voltageNow << " microvolts\n";
    }
    if (snapshot.currentNow) {
        std::cout << "Current: " << *snapshot.currentNow << " microamps\n";
    }
    if (snapshot.energyNow) {
        std::cout << "Energy now: " << *snapshot.energyNow
                  << " microwatt-hours\n";
    }
    if (snapshot.energyFull) {
        std::cout << "Energy full: " << *snapshot.energyFull
                  << " microwatt-hours\n";
    }
    if (snapshot.chargeNow) {
        std::cout << "Charge now: " << *snapshot.chargeNow << '\n';
    }
    if (snapshot.chargeFull) {
        std::cout << "Charge full: " << *snapshot.chargeFull << '\n';
    }
}

void sendNotification(const std::string& title, const std::string& body) {
    const pid_t child = fork();
    if (child < 0) {
        std::cerr << "battery monitor: could not start notify-send\n";
        return;
    }
    if (child == 0) {
        execlp("notify-send", "notify-send",
               "--app-name=NEO Battery Monitor", "--urgency=normal",
               "--icon=battery", "--expire-time=10000",
               title.c_str(), body.c_str(), static_cast<char*>(nullptr));
        _exit(127);
    }

    int status = 0;
    while (waitpid(child, &status, 0) < 0) {
        if (errno != EINTR) {
            std::cerr << "battery monitor: waitpid failed\n";
            return;
        }
    }
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        std::cerr << "battery monitor: notification delivery failed for: "
                  << title << '\n';
    }
}

int runMonitor() {
    udev* context = udev_new();
    udev_monitor* monitor = nullptr;
    int monitorFd = -1;

    if (context != nullptr) {
        monitor = udev_monitor_new_from_netlink(context, "kernel");
        if (monitor != nullptr &&
            udev_monitor_filter_add_match_subsystem_devtype(
                monitor, "power_supply", nullptr) == 0 &&
            udev_monitor_enable_receiving(monitor) == 0) {
            monitorFd = udev_monitor_get_fd(monitor);
        } else {
            std::cerr << "battery monitor: udev listener unavailable; "
                         "using one-second polling\n";
        }
    } else {
        std::cerr << "battery monitor: udev unavailable; using one-second polling\n";
    }

    const Snapshot initial = readSnapshot();
    std::optional<bool> previousExternalPower = initial.externalPowerOnline;

    while (running != 0) {
        if (monitorFd >= 0) {
            pollfd descriptor{};
            descriptor.fd = monitorFd;
            descriptor.events = POLLIN;
            const int result = poll(&descriptor, 1, 1000);
            if (result < 0 && errno != EINTR) {
                std::cerr << "battery monitor: udev poll failed; "
                             "using one-second polling\n";
                monitorFd = -1;
            } else if (result > 0 && (descriptor.revents & POLLIN) != 0) {
                while (udev_device* device = udev_monitor_receive_device(monitor)) {
                    udev_device_unref(device);
                }
            }
        } else {
            poll(nullptr, 0, 1000);
        }

        if (running == 0) {
            break;
        }

        const Snapshot current = readSnapshot();
        if (previousExternalPower && current.externalPowerOnline &&
            *previousExternalPower != *current.externalPowerOnline) {
            if (*current.externalPowerOnline) {
                sendNotification("Charger connected", "External power is connected.");
            } else {
                sendNotification("Charger disconnected", "The laptop is running on battery.");
            }
        }
        if (current.externalPowerOnline) {
            previousExternalPower = current.externalPowerOnline;
        }
    }

    if (monitor != nullptr) {
        udev_monitor_unref(monitor);
    }
    if (context != nullptr) {
        udev_unref(context);
    }
    return 0;
}

} // namespace

int main(int argc, char* argv[]) {
    std::signal(SIGINT, handleSignal);
    std::signal(SIGTERM, handleSignal);

    if (argc == 2 && std::string(argv[1]) == "--check") {
        printCheck();
        return 0;
    }
    if (argc == 2 && std::string(argv[1]) == "--status") {
        printStatus();
        return 0;
    }
    if (argc == 2 && (std::string(argv[1]) == "--help" ||
                      std::string(argv[1]) == "-h")) {
        std::cout << "NEO Battery Monitor v0.1\n\n"
                     "Usage:\n"
                     "  neo-battery-monitor          Monitor charger changes\n"
                     "  neo-battery-monitor --check   Inspect battery hardware\n"
                     "  neo-battery-monitor --status  Print one i3blocks status line\n"
                     "  neo-battery-monitor --help    Show this help\n";
        return 0;
    }
    if (argc != 1) {
        std::cerr << "Unknown argument. Use --help.\n";
        return 2;
    }
    return runMonitor();
}
