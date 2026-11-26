#!/usr/bin/env bash
# Solar2D Installer for x86-64 Linux (Debian/Ubuntu base).
# Run as your normal user: bash install-solar2d.sh
set -Eeuo pipefail
trap 'printf "Installation stopped at line %s. Fix the error above and rerun.\n" "$LINENO" >&2' ERR
fail() { printf '%s\n' "$*" >&2; exit 1; }
(( EUID != 0 )) || fail 'Run as your normal user, not with sudo.'

[[ $(uname -m) == x86_64 ]] || fail 'An x86-64 system is required.'
export LANG=C.UTF-8 LC_ALL=C.UTF-8 LANGUAGE=en

echo "Buscando informações da última versão do Solar2D no GitHub..."
LATEST_JSON=$(curl -s https://api.github.com/repos/coronalabs/corona/releases/latest)

BUILD_NUMBER=$(echo "$LATEST_JSON" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
MSI_URL=$(echo "$LATEST_JSON" | grep "browser_download_url" | grep -i "\.msi" | cut -d '"' -f 4 | head -n 1)
MSI_FILE=$(basename "$MSI_URL")
YEAR=$(echo "$MSI_FILE" | sed -n 's/.*-\([0-9]\{4\}\)\..*/\1/p')

if [[ -z "$BUILD_NUMBER" ]] || [[ -z "$MSI_URL" ]]; then
    fail "Falha ao obter a última versão do Github. Verifique sua conexão com a internet."
fi

echo "Última versão encontrada: $YEAR.$BUILD_NUMBER"
echo "Preparando instalação..."

root="$HOME/.local/share/solar2d-${YEAR}.${BUILD_NUMBER}"
src="$root/source"
build="$root/build"
mkdir -p "$root"
exec > >(tee -a "$root/install.log") 2>&1
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
    ca-certificates git curl unzip zip msitools build-essential cmake pkg-config \
    zlib1g-dev libgl1-mesa-dev libopenal-dev libfreetype-dev libpng-dev \
    libcurl4-openssl-dev libjpeg-dev libssl-dev libsdl2-dev openjdk-17-jdk-headless

if [[ ! -e "$src" ]]; then
    git clone --depth 1 --branch "$BUILD_NUMBER" https://github.com/coronalabs/corona.git "$src"
fi
git -C "$src" submodule update --init --recursive --jobs 4

msi="$root/$MSI_FILE"
if [[ ! -f "$msi" ]]; then
    curl --fail --location --retry 3 --connect-timeout 30 \
        "$MSI_URL" \
        --output "$msi.part"
    mv "$msi.part" "$msi"
fi
mkdir -p "$root/extracted"
msiextract -C "$root/extracted" "$msi" > "$root/extraction.log"
resources="$root/extracted/Program Files/Corona Labs/Corona"
for archive in "$resources/Resources/webtemplate.zip" \
    "$resources/Native/Corona/android/resource/android-template.zip" \
    "$resources/Native/Corona/android/lib/gradle/Corona.aar"; do
    unzip -tqq "$archive"
done

export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export PATH="$JAVA_HOME/bin:$PATH"
java -version
jarsigner -help > /dev/null

export YEAR="$YEAR" BUILD_NUMBER="$BUILD_NUMBER"
cmake -S "$src" -B "$build" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    '-DCMAKE_C_FLAGS=-Wno-error=incompatible-pointer-types -Wno-error=implicit-function-declaration'
cmake --build "$build" --parallel "${JOBS:-2}"
cp "$resources/Resources/webtemplate.zip" "$build/Resources/"
mkdir -p "$build/Resources/Native/Corona"
cp -a "$resources/Native/Corona/android" "$build/Resources/Native/Corona/"
[[ -x "$build/Solar2DSimulator" ]] || fail 'Simulator executable missing.'
tar -tzf "$build/Resources/linuxtemplate_x64.tgz" > /dev/null
ldd "$build/Solar2DSimulator" > "$root/shared-libraries.log"
if grep -q 'not found' "$root/shared-libraries.log"; then
    cat "$root/shared-libraries.log"
    fail 'Missing shared libraries.'
fi

mkdir -p "$HOME/.local/bin"
launcher="$HOME/.local/bin/solar2d-${YEAR}.${BUILD_NUMBER}"
{
    printf '#!/usr/bin/env bash\nset -e\n'
    printf 'export LANG=C.UTF-8 LC_ALL=C.UTF-8 LANGUAGE=en\n'
    printf 'export JAVA_HOME=%q\n' "$JAVA_HOME"
    # shellcheck disable=SC2016
    printf 'export PATH="$JAVA_HOME/bin:$PATH"\n'
    printf 'cd %q\nexec ./Solar2DSimulator "$@"\n' "$build"
} > "$launcher"
chmod +x "$launcher"

sudo mkdir -p /usr/local/bin
sudo ln -sfnT "$launcher" /usr/local/bin/Solar2d
if [[ -L /usr/bin/Solar2d ]]; then
    case "$(readlink /usr/bin/Solar2d)" in
        "$HOME/.local/bin/solar2d-"*) sudo unlink /usr/bin/Solar2d ;;
    esac
fi

# Limpeza automática de versões antigas após a instalação bem-sucedida
echo "Verificando e removendo versões antigas do Solar2D..."
for old_dir in "$HOME/.local/share"/solar2d-*; do
    if [[ -d "$old_dir" && "$old_dir" != "$root" ]]; then
        echo "Removendo pasta antiga: $old_dir"
        rm -rf "$old_dir"
    fi
done

for old_bin in "$HOME/.local/bin"/solar2d-*; do
    if [[ -f "$old_bin" && "$old_bin" != "$launcher" ]]; then
        echo "Removendo lançador antigo: $old_bin"
        rm -f "$old_bin"
    fi
done

# Criação automática do ícone e atalho no menu de aplicativos
echo "Configurando ícone e atalho no menu de aplicativos..."
mkdir -p "$HOME/.local/share/icons" "$HOME/.local/share/applications"

icon_dest="$HOME/.local/share/icons/solar2d-local.png"
img_found=$(find "$root" -type f -iname "solar2d*.png" | head -n 1 || true)

if [[ -n "$img_found" && -f "$img_found" ]]; then
    cp "$img_found" "$icon_dest"
else
    curl -sL "https://avatars.githubusercontent.com/u/62804595?s=256&v=4" -o "$icon_dest" || true
fi

desktop_file="$HOME/.local/share/applications/solar2d.desktop"
cat << EOF > "$desktop_file"
[Desktop Entry]
Name=Solar2D
Comment=Motor 2D para criação de jogos e apps
Exec=/usr/local/bin/Solar2d
Icon=$icon_dest
Terminal=false
Type=Application
Categories=Development;IDE;
EOF
chmod +x "$desktop_file"
update-desktop-database "$HOME/.local/share/applications/" 2>/dev/null || true

printf '\nInstalled. Launch with: Solar2d (or from the Applications menu)\n'
printf 'Launcher: %s\n' "$launcher"
printf 'Android exports require Internet access for Gradle/SDK dependencies.\n'
printf 'The first Android build can take much longer while dependencies download.\n'
