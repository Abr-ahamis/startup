

cd ~/Work/Docker/window
## stoping other docker
sudo docker compose down

## Remove old brocking file and new 
sudo rm -rf ./win_storage
mkdir -p ./win_storage

## checking
sudo docker compose config | grep -A6 -B2 DISK_SIZE



## startup
sudo docker compose up -d --force-recreate


# starting
sudo docker compose start

# stoping
sudo docker compose stop

## Checking 
sudo docker inspect windows_lite_desktop \
  --format '{{range .Config.Env}}{{println .}}{{end}}' | grep '^DISK_SIZE='


## loging
sudo docker compose logs -f
