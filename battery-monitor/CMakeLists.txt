cmake_minimum_required(VERSION 3.16)

project(neo-battery-monitor VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(PkgConfig REQUIRED)
pkg_check_modules(UDEV REQUIRED IMPORTED_TARGET libudev)

add_executable(neo-battery-monitor src/main.cpp)
target_link_libraries(neo-battery-monitor PRIVATE PkgConfig::UDEV)
target_compile_options(neo-battery-monitor PRIVATE
    -Wall -Wextra -Wpedantic -Wconversion -Wshadow
)

install(TARGETS neo-battery-monitor RUNTIME DESTINATION bin)
