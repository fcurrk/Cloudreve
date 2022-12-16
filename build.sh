#!/bin/bash
appName="cloudreve"
REPO=$(
  cd $(dirname $0)
  pwd
)
COMMIT_SHA=$(git rev-parse --short HEAD)
#VERSION=$(git describe --tags)
VERSION="3.6.0.3"
ASSETS="false"
BINARY="false"
RELEASE="false"

ldflags="\
-w -s \
-X 'github.com/cloudreve/Cloudreve/v3/pkg/conf.BackendVersion=$VERSION' \
-X 'github.com/cloudreve/Cloudreve/v3/pkg/conf.LastCommit=$COMMIT_SHA' \
"

debugInfo() {
  echo "Repo:           $REPO"
  echo "Build assets:   $ASSETS"
  echo "Build binary:   $BINARY"
  echo "Release:        $RELEASE"
  echo "Version:        $VERSION"
  echo "Commit:        $COMMIT_SHA"
}

buildAssets() {
  cd $REPO
  rm -rf assets/build

  export CI=false
  export GENERATE_SOURCEMAP=false

  cd $REPO/assets

  yarn install
  yarn run build
  cd build
  cd $REPO

  # please keep in mind that if this final output binary `assets.zip` name changed, please go and update the `Dockerfile` as well
  zip -r - assets/build >assets.zip
}

buildBinary() {
  cd $REPO

  # same as assets, if this final output binary `cloudreve` name changed, please go and update the `Dockerfile`
  go build -a -o cloudreve -ldflags="$ldflags"
}

_build() {
  local osarch=$1
  IFS=/ read -r -a arr <<<"$osarch"
  os="${arr[0]}"
  arch="${arr[1]}"
  gcc="${arr[2]}"

  # Go build to build the binary.
  export GOOS=$os
  export GOARCH=$arch
  export CC=$gcc
  export CGO_ENABLED=1

  if [ -n "$VERSION" ]; then
    out="release/cloudreve_${VERSION}_${os}_${arch}"
  else
    out="release/cloudreve_${COMMIT_SHA}_${os}_${arch}"
  fi

  go build -a -o "${out}" -ldflags="$ldflags"

  if [ "$os" = "windows" ]; then
    mv $out release/cloudreve.exe
    zip -j -q "${out}.zip" release/cloudreve.exe
    rm -f "release/cloudreve.exe"
  else
    mv $out release/cloudreve
    tar -zcvf "${out}.tar.gz" -C release cloudreve
    rm -f "release/cloudreve"
  fi
}

release() {
  rm -rf .git/
  mkdir -p "build"
  muslflags="--extldflags '-static -fpic' $ldflags"
  BASE="https://musl.nn.ci/"
  FILES=(x86_64-linux-musl-cross aarch64-linux-musl-cross arm-linux-musleabihf-cross)
  for i in "${FILES[@]}"; do
    url="${BASE}${i}.tgz"
    curl -L -o "${i}.tgz" "${url}"
    sudo tar xf "${i}.tgz" --strip-components 1 -C /usr/local
  done
  OS_ARCHES=(linux-musl-amd64 linux-musl-arm64 linux-musl-arm)
  CGO_ARGS=(x86_64-linux-musl-gcc aarch64-linux-musl-gcc arm-linux-musleabihf-gcc)
  for i in "${!OS_ARCHES[@]}"; do
    os_arch=${OS_ARCHES[$i]}
    cgo_cc=${CGO_ARGS[$i]}
    echo building for ${os_arch}
    export GOOS=${os_arch%%-*}
    export GOARCH=${os_arch##*-}
    export CC=${cgo_cc}
    export CGO_ENABLED=1
    go build -o ./build/$appName-$os_arch -ldflags="$muslflags" -tags=jsoniter .
  done
  xgo -targets=linux/amd64,windows/amd64,linux/arm64 -out "$appName" -ldflags="$ldflags" -tags=jsoniter .
  # why? Because some target platforms seem to have issues with upx compression
  upx -9 ./cloudreve-linux-amd64
  upx -9 ./cloudreve-windows*
  mv cloudreve-* build
  cd build
  find . -type f -print0 | xargs -0 md5sum >md5.txt
  cat md5.txt
}

usage() {
  echo "Usage: $0 [-a] [-c] [-b] [-r]" 1>&2
  exit 1
}

while getopts "bacrd" o; do
  case "${o}" in
  b)
    ASSETS="true"
    BINARY="true"
    ;;
  a)
    ASSETS="true"
    ;;
  c)
    BINARY="true"
    ;;
  r)
    ASSETS="true"
    RELEASE="true"
    ;;
  d)
    DEBUG="true"
    ;;
  *)
    usage
    ;;
  esac
done
shift $((OPTIND - 1))

if [ "$DEBUG" = "true" ]; then
  debugInfo
fi

if [ "$ASSETS" = "true" ]; then
  buildAssets
fi

if [ "$BINARY" = "true" ]; then
  buildBinary
fi

if [ "$RELEASE" = "true" ]; then
  release
fi
