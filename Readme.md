docker build -t powershell-alpine .

docker run -e DEVICE_USER="admin" -e DEVICE_PASSWORD="changeme" -p 8080:8080 --rm -it powershell-alpine


