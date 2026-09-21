#!/bin/zsh

set -euo pipefail

if (( $# > 0 )); then
    print -u2 "Usage: $0"
    exit 2
fi

script_directory=${0:A:h}
repository_root=${script_directory:h}
info_plist_path="$repository_root/Sources/PulseNotchApp/Info.plist"
info_plist_relative_path="Sources/PulseNotchApp/Info.plist"

cd "$repository_root"

if [[ "$(git branch --show-current)" != "main" ]]; then
    print -u2 "Releases must be prepared from the main branch."
    exit 1
fi

if ! git diff --quiet -- "$info_plist_relative_path" ||
   ! git diff --cached --quiet -- "$info_plist_relative_path"; then
    print -u2 "$info_plist_relative_path has uncommitted changes."
    exit 1
fi

current_version=$(plutil -extract CFBundleShortVersionString raw "$info_plist_path")
build_number=$(plutil -extract CFBundleVersion raw "$info_plist_path")

if [[ ! "$current_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ "$build_number" != <-> ]]; then
    print -u2 "Info.plist must contain an X.Y.Z version and a numeric build number."
    exit 1
fi

major=${current_version%%.*}
remainder=${current_version#*.}
minor=${remainder%%.*}
patch=${remainder#*.}

print "Current version: $current_version (build $build_number)"
while true; do
    printf "Release type (major/minor/patch): "
    read -r release_type || exit 1

    case "$release_type" in
        major)
            next_version="$((major + 1)).0.0"
            break
            ;;
        minor)
            next_version="$major.$((minor + 1)).0"
            break
            ;;
        patch)
            next_version="$major.$minor.$((patch + 1))"
            break
            ;;
        *) print -u2 "Choose major, minor, or patch." ;;
    esac
done

next_build=$((build_number + 1))
tag="v$next_version"

if git show-ref --verify --quiet "refs/tags/$tag" ||
   git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1; then
    print -u2 "Tag $tag already exists."
    exit 1
fi

printf "Release $next_version (build $next_build), commit it, and push main and $tag? [y/N] "
read -r confirmation || exit 1
if [[ "$confirmation" != [yY] ]]; then
    print "Release cancelled."
    exit 0
fi

plutil -replace CFBundleShortVersionString -string "$next_version" "$info_plist_path"
plutil -replace CFBundleVersion -string "$next_build" "$info_plist_path"

swift test
git add "$info_plist_relative_path"
git commit --only "$info_plist_relative_path" -m "chore: prepare release $next_version"
git push origin main
git tag -a "$tag" -m "Pulse Notch $next_version"
git push origin "$tag"

print "Released $next_version (build $next_build)."
