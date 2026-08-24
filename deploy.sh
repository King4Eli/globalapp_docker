CONFIG=".env/deploy.json"

imageName=""
listImages=false
allImages=false
createConfig=false

usage() {
    echo "Usage: $0 [-l|--list] [-i <imageName>] [-A|--all] [--create]"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -i)
            if [[ -z "${2:-}" ]]; then
                usage
                exit 1
            fi
            imageName="$2"
            shift 2
            ;;
        --list|-l)
            listImages=true
            shift
            ;;
        -A|--all)
            allImages=true
            shift
            ;;
        --create)
            createConfig=true
            shift
            ;;
        *)
            usage
            exit 1
            ;;
    esac
done

if $createConfig; then
    if [[ -e "$CONFIG" ]]; then
        echo "$CONFIG already exists -- not overwriting"
        exit 1
    fi
    mkdir -p "$(dirname "$CONFIG")"
    cat > "$CONFIG" <<'JSON'
{
  "suyoapp_com_api": {
    "host": {
      "url": "ghcr.io",
      "username": "kingeli",
      "appversion": "1.0.0",
      "buildfolder": "./api_v1"
    },
    "ssh": {
      "start": true,
      "username": "server_username",
      "server": "192.168.15.61",
      "path": "$HOME/proj/app_1",
      "command": []
    }
  }
}
JSON
    echo "Created template $CONFIG"
    exit 0
fi

if $listImages; then
    jq -r 'keys[]' "$CONFIG"
    exit 0
fi

if $allImages && [[ -n "$imageName" ]]; then
    echo "-A/--all cannot be combined with -i"
    usage
    exit 1
fi

deployImage() {
    local imageName="$1"

    # Verify the key exists
    if ! jq -e --arg img "$imageName" '.[$img]' "$CONFIG" >/dev/null; then
        echo "Image '$imageName' not found in $CONFIG"
        exit 1
    fi

    local hostUrl username version buildFolder imageRepo
    hostUrl=$(jq -r --arg img "$imageName" '.[$img].host.url // empty' "$CONFIG")
    username=$(jq -r --arg img "$imageName" '.[$img].host.username // empty' "$CONFIG")
    version=$(jq -r --arg img "$imageName" '.[$img].host.appversion' "$CONFIG")
    buildFolder=$(jq -r --arg img "$imageName" '.[$img].host.buildfolder' "$CONFIG")

    if [[ ! -d "$buildFolder" ]]; then
        echo "buildfolder '$buildFolder' not found for '$imageName'" >&2
        exit 1
    fi

    # .host.url: optional -- omit for Docker Hub, or set for a private registry.
    # .host.username: required unless .url is set (Docker Hub always needs a namespace;
    # a private registry may not).
    if [[ -z "$hostUrl" && -z "$username" ]]; then
        echo "host.username is required when host.url is not set" >&2
        exit 1
    fi

    if [[ -n "$hostUrl" ]]; then
        if [[ -n "$username" ]]; then
            imageRepo="$hostUrl/$username/$imageName"
        else
            imageRepo="$hostUrl/$imageName"
        fi
    else
        imageRepo="$username/$imageName"
    fi

    local sshStartRun sshUsername sshServer sshPath sshCommand
    sshStartRun=$(jq -r --arg img "$imageName" '.[$img].ssh.start' "$CONFIG")
    sshUsername=$(jq -r --arg img "$imageName" '.[$img].ssh.username' "$CONFIG")
    sshServer=$(jq -r --arg img "$imageName" '.[$img].ssh.server' "$CONFIG")
    sshPath=$(jq -r --arg img "$imageName" '.[$img].ssh.path' "$CONFIG")
    # .ssh.command: array, joined with && after trimming trailing `;`.
    sshCommand=$(jq -r --arg img "$imageName" \
        '.[$img].ssh.command | map(sub("[;[:space:]]+$"; "")) | join(" && ")' \
        "$CONFIG")

    echo ""
    echo "=================$imageName=================="

    docker build \
        -t "$imageRepo:$version" \
        -t "$imageRepo:latest" \
        "$buildFolder"

    docker push "$imageRepo:$version"
    docker push "$imageRepo:latest"

    if [ "$sshStartRun" = "true" ]; then
        echo ""
        echo "=================ssh=================="
        ssh "$sshUsername@$sshServer" <<EOF
set -e
cd "$sshPath"
$sshCommand
EOF
    fi
}

if $allImages; then
    while IFS= read -r img; do
        deployImage "$img"
    done < <(jq -r 'keys[]' "$CONFIG")
    exit 0
fi

if [[ -z "$imageName" ]]; then
    imageCount=$(jq -r 'keys | length' "$CONFIG")
    if [[ "$imageCount" -eq 1 ]]; then
        imageName=$(jq -r 'keys[0]' "$CONFIG")
    else
        echo "Multiple images found in $CONFIG -- specify one with: $0 -i <imageName>, or use -A/--all to deploy all"
        jq -r 'keys[]' "$CONFIG"
        exit 1
    fi
fi

deployImage "$imageName"
