#!/usr/bin/env bash
# Solar2D Installer for x86-64 Linux (Debian/Ubuntu base).
# Run as your normal user: bash install-solar2d.sh
set -Eeuo pipefail
trap 'printf "Installation stopped at line %s. Fix the error above and rerun.\n" "$LINENO" >&2' ERR
fail() { printf '%s\n' "$*" >&2; exit 1; }
(( EUID != 0 )) || fail 'Run as your normal user, not with sudo.'

# 1. Removed the Linux Mint check (os-release).
# Kept only the architecture check (must be 64-bit).
[[ $(uname -m) == x86_64 ]] || fail 'An x86-64 system is required.'
export LANG=C.UTF-8 LC_ALL=C.UTF-8 LANGUAGE=en

# 2. Automatic retrieval of the latest version from GitHub (Tags, Year, and MSI link)
echo "Buscando informações da última versão do Solar2D no GitHub..."
LATEST_JSON=$(curl -s https://api.github.com/repos/coronalabs/corona/releases/latest)

# Extracts the build number (e.g., 3737) and the MSI download URL
BUILD_NUMBER=$(echo "$LATEST_JSON" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
MSI_URL=$(echo "$LATEST_JSON" | grep "browser_download_url" | grep -i "\.msi" | cut -d '"' -f 4 | head -n 1)
MSI_FILE=$(basename "$MSI_URL")
YEAR=$(echo "$MSI_FILE" | sed -n 's/.*-\([0-9]\{4\}\)\..*/\1/p') # Get the year from the filename

if [[ -z "$BUILD_NUMBER" ]] || [[ -z "$MSI_URL" ]]; then
    fail "Falha ao obter a última versão do Github. Verifique sua conexão com a internet."
fi

echo "Latest version found: $YEAR.$BUILD_NUMBER"
echo "Preparing installation..."

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

# Extract portable export resources without installing Windows software or Snap.
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

# A launcher keeps Java and English locale settings local to Solar2D.
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

# Keep the command stable when an updated installer changes the launcher version.
sudo mkdir -p /usr/local/bin
sudo ln -sfnT "$launcher" /usr/local/bin/Solar2d
# Remove only the old link created for this user's versioned launchers.
if [[ -L /usr/bin/Solar2d ]]; then
    case "$(readlink /usr/bin/Solar2d)" in
        "$HOME/.local/bin/solar2d-"*) sudo unlink /usr/bin/Solar2d ;;
    esac
fi
printf '\nInstalled. Launch with: Solar2d\n'
printf 'Launcher: %s\n' "$launcher"
printf 'Android exports require Internet access for Gradle/SDK dependencies.\n'
printf 'The first Android build can take much longer while dependencies download.\n'
