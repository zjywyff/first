#!/bin/bash

# This script builds and archives binaries and supporting files for mac, linux, and windows.
# If directory ./server/static exists, it's asumed to contain TinodeWeb and then it's also
# copied and archived.

# Supported OSs: mac (darwin), windows, linux.
goplat=( darwin darwin windows linux linux )

# CPUs architectures: amd64 and arm64. The same order as OSs.
goarc=( amd64 arm64 amd64 amd64 arm64 )

# Number of platform+architectures.
buildCount=${#goplat[@]}

# Supported database tags
dbadapters=( mysql mongodb rethinkdb postgres )
dbtags=( ${dbadapters[@]} alldbs )

for line in $@; do
  eval "$line"
done

version=${tag#?}

if [ -z "$version" ]; then
  # Get last git tag as release version. Tag looks like 'v.1.2.3', so strip 'v'.
  version=`git describe --tags`
  version=${version#?}
fi

echo "Releasing $version"

GOSRC=..

pushd ${GOSRC}/chat > /dev/null

# Prepare directory for the new release
rm -fR ./releases/${version}
mkdir ./releases/${version}

# Tar on Mac is inflexible about directories. Let's just copy release files to
# one directory.
rm -fR ./releases/tmp
mkdir -p ./releases/tmp/templ

# Copy templates and database initialization files
cp ./server/tinode.conf ./releases/tmp
cp ./server/templ/*.templ ./releases/tmp/templ
cp ./tinode-db/data.json ./releases/tmp
cp ./tinode-db/*.jpg ./releases/tmp
cp ./tinode-db/credentials.sh ./releases/tmp

# Create directories for and copy TinodeWeb files.
if [[ -d ./server/static ]]
then
  mkdir -p ./releases/tmp/static/img
  mkdir ./releases/tmp/static/css
  mkdir ./releases/tmp/static/audio
  mkdir ./releases/tmp/static/src
  mkdir ./releases/tmp/static/umd

  cp ./server/static/img/*.png ./releases/tmp/static/img
  cp ./server/static/img/*.svg ./releases/tmp/static/img
  cp ./server/static/img/*.jpeg ./releases/tmp/static/img
  cp ./server/static/audio/*.m4a ./releases/tmp/static/audio
  cp ./server/static/css/*.css ./releases/tmp/static/css
  cp ./server/static/index.html ./releases/tmp/static
  cp ./server/static/index-dev.html ./releases/tmp/static
  cp ./server/static/version.js ./releases/tmp/static
  cp ./server/static/umd/*.js ./releases/tmp/static/umd
  cp ./server/static/manifest.json ./releases/tmp/static
  cp ./server/static/service-worker.js ./releases/tmp/static
  # Create empty FCM client-side config.
  echo 'const FIREBASE_INIT = {};' > ./releases/tmp/static/firebase-init.js
else
  echo "TinodeWeb not found, skipping"
fi

for (( i=0; i<${buildCount}; i++ ));
do
  plat="${goplat[$i]}"
  arc="${goarc[$i]}"

  # Use .exe file extension for binaries on Windows.
  ext=""
  if [ "$plat" = "windows" ]; then
    ext=".exe"
  fi

  # Remove possibly existing keygen from previous build.
  rm -f ./releases/tmp/keygen
  rm -f ./releases/tmp/keygen.exe

  # Keygen is database-independent
  env GOOS="${plat}" GOARCH="${arc}" go build -ldflags "-s -w" -o ./releases/tmp/keygen${ext} ./keygen > /dev/null

  for dbtag in "${dbtags[@]}"
  do
    echo "Building ${dbtag}-${plat}/${arc}..."

    # Remove possibly existing binaries from previous build.
    rm -f ./releases/tmp/tinode
    rm -f ./releases/tmp/tinode.exe
    rm -f ./releases/tmp/init-db
    rm -f ./releases/tmp/init-db.exe

    # Build tinode server and database initializer for RethinkDb and MySQL.
    # For 'alldbs' tag, we compile in all available DB adapters.
    if [ "$dbtag" = "alldbs" ]; then
      buildtag="${dbadapters[@]}"
    else
      buildtag=$dbtag
    fi

    env GOOS="${plat}" GOARCH="${arc}" go build \
      -ldflags "-s -w -X main.buildstamp=`git describe --tags`" -tags "${buildtag}" \
      -o ./releases/tmp/tinode${ext} ./server > /dev/null
    env GOOS="${plat}" GOARCH="${arc}" go build \
      -ldflags "-s -w" -tags "${buildtag}" -o ./releases/tmp/init-db${ext} ./tinode-db > /dev/null

    # Build archive. All platforms but Windows use tar for archiving. Windows uses zip.
    if [ "$plat" = "windows" ]; then
      # Remove possibly existing archive.
      rm -f ./releases/${version}/tinode-${dbtag}."${plat}-${arc}".zip
      # Generate a new one
      pushd ./releases/tmp > /dev/null
      zip -q -r ../${version}/tinode-${dbtag}."${plat}-${arc}".zip ./*
      popd > /dev/null
    else
      plat2=$plat
      # Rename 'darwin' tp 'mac'
      if [ "$plat" = "darwin" ]; then
        plat2=mac
      fi

      # Remove possibly existing archive.
      rm -f ./releases/${version}/tinode-${dbtag}."${plat2}-${arc}".tar.gz
      # Generate a new one
      tar -C ./releases/tmp -zcf ./releases/${version}/tinode-${dbtag}."${plat2}-${arc}".tar.gz .
    fi
  done
done

# Build chatbot release
echo "Building python code..."

./build-py-grpc.sh

# Release chatbot
echo "Packaging chatbot.py..."
rm -fR ./releases/tmp
mkdir -p ./releases/tmp

cp ${GOSRC}/chat/chatbot/python/chatbot.py ./releases/tmp
cp ${GOSRC}/chat/chatbot/python/quotes.txt ./releases/tmp
cp ${GOSRC}/chat/chatbot/python/requirements.txt ./releases/tmp

tar -C ${GOSRC}/chat/releases/tmp -zcf ./releases/${version}/py-chatbot.tar.gz .
pushd ./releases/tmp > /dev/null
zip -q -r ../${version}/py-chatbot.zip ./*
popd > /dev/null

# Release tn-cli
echo "Packaging tn-cli..."

rm -fR ./releases/tmp
mkdir -p ./releases/tmp

cp ${GOSRC}/chat/tn-cli/*.py ./releases/tmp
cp ${GOSRC}/chat/tn-cli/*.txt ./releases/tmp

tar -C ${GOSRC}/chat/releases/tmp -zcf ./releases/${version}/tn-cli.tar.gz .
pushd ./releases/tmp > /dev/null
zip -q -r ../${version}/tn-cli.zip ./*
popd > /dev/null

# Clean up temporary files
rm -fR ./releases/tmp

popd > /dev/null
