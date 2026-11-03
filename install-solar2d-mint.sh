#!/usr/bin/env bash
# Solar2D 2026.3736 for x86-64 Linux Mint 22.x (Ubuntu 24.04 base).
# User confirmed Linux, HTML5 and Android exports work with this release.
# Run as your normal user: bash install-solar2d-mint.sh
set -Eeuo pipefail
trap 'printf "Installation stopped at line %s. Fix the error above and rerun.\n" "$LINENO" >&2' ERR
fail() { printf '%s\n' "$*" >&2; exit 1; }
(( EUID != 0 )) || fail 'Run as your normal user, not with sudo.'
# shellcheck disable=SC1091
source /etc/os-release
[[ ${ID:-} == linuxmint && ${VERSION_ID:-} == 22* ]] ||
    fail 'This script targets Linux Mint 22.x; other releases are not validated.'
[[ $(uname -m) == x86_64 ]] || fail 'An x86-64 system is required.'
export LANG=C.UTF-8 LC_ALL=C.UTF-8 LANGUAGE=en

revision=d74923057d3fc3abad1903b61de5a459d9566363
root="$HOME/.local/share/solar2d-2026.3736"
src="$root/source"
build="$root/build"
mkdir -p "$root"
exec > >(tee -a "$root/install.log") 2>&1
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
    ca-certificates git curl unzip zip msitools build-essential cmake pkg-config \
    zlib1g-dev libgl1-mesa-dev libopenal-dev libfreetype-dev libpng-dev \
    libcurl4-openssl-dev libjpeg-dev libssl-dev libsdl2-dev openjdk-17-jdk-headless

# Use the exact release reviewed; never reset or delete an existing checkout.
if [[ ! -e "$src" ]]; then
    git clone --depth 1 --branch 3736 https://github.com/coronalabs/corona.git "$src"
fi
[[ $(git -C "$src" rev-parse HEAD) == "$revision" ]] || fail "Unexpected source revision: $src"
git -C "$src" submodule update --init --recursive --jobs 4

# Extract portable export resources without installing Windows software or Snap.
msi="$root/Solar2D-Windows-2026.3736.msi"
checksum=5a97b88f4c775507e3d5bd3f2c5f514d4313bbdeca0d4b299830095b36314d17
if [[ ! -f "$msi" ]]; then
    curl --fail --location --retry 3 --connect-timeout 30 \
        https://github.com/coronalabs/corona/releases/download/3736/Solar2D-Windows-2026.3736.msi \
        --output "$msi.part"
    mv "$msi.part" "$msi"
fi
printf '%s  %s\n' "$checksum" "$msi" | sha256sum --check -
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
export YEAR=2026 BUILD_NUMBER=3736
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
launcher="$HOME/.local/bin/solar2d-2026.3736"
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