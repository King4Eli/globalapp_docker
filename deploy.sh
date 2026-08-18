CONFIG=".env/deploy.json"

imageName=""
listImages=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -i)
            imageName="$2"
            shift 2
            ;;
        --list|-l)
            listImages=true
            shift
            ;;
        *)
            echo "Usage: $0 [-l|--list] [-i <imageName>]"
            exit 1
            ;;
    esac
done

if $listImages; then
    jq -r 'keys[]' "$CONFIG"
    exit 0
fi

if [[ -z "$imageName" ]]; then
    imageCount=$(jq -r 'keys | length' "$CONFIG")
    if [[ "$imageCount" -eq 1 ]]; then
        imageName=$(jq -r 'keys[0]' "$CONFIG")
    else
        echo "Multiple images found in $CONFIG -- specify one with: $0 -i <imageName>"
        jq -r 'keys[]' "$CONFIG"
        exit 1
    fi
fi

# Verify the key exists
if ! jq -e --arg img "$imageName" '.[$img]' "$CONFIG" >/dev/null; then
    echo "Image '$imageName' not found in $CONFIG"
    exit 1
fi

username=$(jq -r --arg img "$imageName" '.[$img].dockerrepo.username' "$CONFIG")
version=$(jq -r --arg img "$imageName" '.[$img].dockerrepo.appversion' "$CONFIG")
buildFolder=$(jq -r --arg img "$imageName" '.[$img].dockerrepo.buildfolder' "$CONFIG")

sshStartRun=$(jq -r --arg img "$imageName" '.[$img].ssh.start' "$CONFIG")
sshUsername=$(jq -r --arg img "$imageName" '.[$img].ssh.username' "$CONFIG")
sshServer=$(jq -r --arg img "$imageName" '.[$img].ssh.server' "$CONFIG")
sshPath=$(jq -r --arg img "$imageName" '.[$img].ssh.path' "$CONFIG")
# .ssh.command: string (legacy) or array, joined with && after trimming trailing `;`.
sshCommand=$(jq -r --arg img "$imageName" \
    '.[$img].ssh.command
     | if type == "array"
       then map(sub("[;[:space:]]+$"; "")) | join(" && ")
       else . end' \
    "$CONFIG")

docker build \
    -t "$username/$imageName:$version" \
    -t "$username/$imageName:latest" \
    "$buildFolder"

docker push "$username/$imageName:$version"
docker push "$username/$imageName:latest"


if [ "$sshStartRun" = "true" ]; then
    echo ""
    echo "=================ssh=================="
    ssh "$sshUsername@$sshServer" <<EOF
set -e
cd "$sshPath"
$sshCommand
EOF
fi

# {
#   "suyoapp_com_api": {
#     "dockerrepo": {
#       "username": "kingeli",
#       "appversion": "1.0.0",
#       "buildfolder": "./api_v1"
#     },
#     "ssh": {
#       "start": true,
#       "username": "server_username",
#       "server": "192.168.15.61",
#       "path": "$HOME/proj/app_1",
#       "command": "export APP_VERSION=1.0.0 docker compose pull && docker compose up mail_justu_server -d"
#     }
#   },
# }