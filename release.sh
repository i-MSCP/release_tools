#!/bin/sh
# i-MSCP - internet Multi Server Control Panel
# Copyright (C) 2010-2018 by internet Multi Server Control Panel
#
# @author    Laurent Declercq <l.declercq@nuxwin.com>
# @link      https://i-mscp.net
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA

set -e

# Command line options
usage() {
  local NAME=`basename $0`
  echo "Usage: ./$NAME [OPTION]... RELEASE_BRANCH RELEASE"
  echo ""
  echo "Release new i-MSCP version on GitHub and SourceForge"
  echo ""
  echo "OPTIONS:"
  echo "  -d   Do everything except pushing changes to GitHub and Sourceforge."
  echo "  -f   Sourceforge username (default to nuxwin)."
  echo "  -?,h Show this help."
  echo "  -g   GitHub user (default to nuxwin)."
  echo "  -m   Release manager name (default to Laurent Declercq)."
  echo "  -s   Make use of SUDO(8) for the restricted commands."
  exit 1
}

# Set default option values
RELEASE_MANAGER="Laurent Declercq"
GITHUB_USER="nuxwin"
FTP_USER="nuxwin"
SUDO=""
DRY_RUN=""

# Parse options
while getopts ":b:f:g:m:r:t:sd" option; do
  case ${option} in
    d) DRY_RUN="--dry-run" ;;
    f) FTP_USER=$OPTARG ;;
    g) GITHUB_USER=$OPTARG ;;
    m) RELEASE_MANAGER=$OPTARG ;;
    s) SUDO="sudo" ;;
    \?|h)
      usage
    ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      usage
    ;;
    *)
      echo "Unknown option: -$OPTARG" >& 2
      usage
    ;;
  esac
done
shift $((OPTIND-1))

[ "$#" -eq 2 ] || usage

RELEASE_BRANCH=$1
RELEASE=$2

## Prepare environment

# Variables
CWD=$(pwd)
GIT_FOLDER="imscpgit"
GITHUB_URL="git@github.com:i-MSCP/imscp.git"

## Packages installation
${SUDO} apt-get update
${SUDO} apt-get install curl perl git-core pbzip2 pigz p7zip

if [ ! -d "${GIT_FOLDER}" ]; then
  # Clone repository
  git clone --depth 1 ${GITHUB_URL} ${GIT_FOLDER}
  cd ${GIT_FOLDER}
else
  # Cleanup current (local) branch
  cd ${GIT_FOLDER}
  git clean -dfx
  git reset --hard origin/$(git symbolic-ref --short HEAD)
  git pull
  git remote update origin --prune
fi

git remote set-branches origin ${RELEASE_BRANCH}
git fetch --depth 1 origin ${RELEASE_BRANCH}
git checkout ${RELEASE_BRANCH}

## GitHub (release)

# Variables
RELEASE_MAINT=false
RELEASE_BUILD="$(date -u +"%Y%m%d")00"
RELEASE_TAG=${RELEASE}
if git ls-remote --exit-code --tags origin ${RELEASE_TAG} >/dev/null; then
  RELEASE_MAINT=true
  RELEASE_TAG="${RELEASE}-${RELEASE_BUILD}"
  while git ls-remote --exit-code --tags origin ${RELEASE_TAG} >/dev/null; do
    RELEASE_BUILD=$((RELEASE_BUILD+1));
    RELEASE_TAG="${RELEASE}-${RELEASE_BUILD}"
  done
fi
RELEASE_CHANGELOG_MSG="\n\n`date -u +%Y-%m-%d`: ${RELEASE_MANAGER}\n    RELEASE i-MSCP ${RELEASE} (build ${RELEASE_BUILD})"

# Release preparation
sed -i -nr '1h;1!H;${;g;s/('"Git ${RELEASE_BRANCH}"'\n-+)/\1'"${RELEASE_CHANGELOG_MSG}"'/g;p;}' ./CHANGELOG
sed -i "s/^Git ${RELEASE_BRANCH}/${RELEASE} (build ${RELEASE_BUILD})/" ./CHANGELOG
sed -i "s/\(^Version\s=\).*/\1 ${RELEASE}/" ./configs/*/imscp.conf
sed -i "s/\(^Build\s=\).*/\1 ${RELEASE_BUILD}/" ./configs/*/imscp.conf
sed -i "s/<release_branch>/${RELEASE_BRANCH}/g" ./docs/*/INSTALL.md
sed -i "s/<release_tag>/${RELEASE_TAG}/g" ./docs/*/INSTALL.md
sed -i "s/<release>/${RELEASE}/g" ./docs/${RELEASE_BRANCH}_errata.md
sed -i "s/<release_build>/${RELEASE_BUILD}/g" ./docs/${RELEASE_BRANCH}_errata.md

# Commit changes
git commit -a -m "New release: ${RELEASE} (build ${RELEASE_BUILD})"
git push ${DRY_RUN} origin ${RELEASE_BRANCH}

# Create tag (now done through GitHub API call)
#git tag -f ${RELEASE_TAG} -m "i-MSCP ${RELEASE} (build ${RELEASE_BUILD}) release" origin/${RELEASE_BRANCH}
#git push ${DRY_RUN} origin ${RELEASE_TAG}

#if [ -n "${DRY_RUN}" ]; then
#    # Remove tag in dry-run mode
#    git tag -d ${RELEASE_TAG}
#else
if [ -z "${DRY_RUN}" ]; then
    if [ "${RELEASE_MAINT}" = false ]; then
        RELEASE_DESCRIPTION="Stable Release"
    else
        RELEASE_DESCRIPTION="Maintenance (bugfixes) Release"
    fi

    printf "%b\n" "A new release ${RELEASE_TAG} will be created on GitHub.\nYou will be asked for your GitHub password."
    curl https://api.github.com/repos/i-MSCP/imscp/releases \
      -H "Accept: application/vnd.github.v3+json" \
      -H "Content-Type: text/json; charset=utf-8" \
      -u "${GITHUB_USER}" \
      -X POST \
      --data @- << EOF
{
  "tag_name": "${RELEASE_TAG}",
  "target_commitish": "${RELEASE_BRANCH}",
  "name": "${RELEASE} (build ${RELEASE_BUILD}) Release",
  "body": "${RELEASE_DESCRIPTION}",
  "draft": false,
  "prerelease": false
}
EOF
fi

## SourceForge

# Variables
ARCHIVES_FOLDER="archives"
RELEASE_FOLDER="imscp-${RELEASE_TAG}"

cd ${CWD}

# Create release folder
rm -fR ${RELEASE_FOLDER}
cp -a  ${GIT_FOLDER} ${RELEASE_FOLDER}
rm -fR ${RELEASE_FOLDER}/.git

# Create archives folders
rm -fr ${ARCHIVES_FOLDER};
mkdir ${ARCHIVES_FOLDER};

# Create various archives
tar -I pbzip2 -cf ${ARCHIVES_FOLDER}/${RELEASE_FOLDER}.tar.bz2 ./${RELEASE_FOLDER}
tar -I pigz -cf ${ARCHIVES_FOLDER}/${RELEASE_FOLDER}.tar.gz ./${RELEASE_FOLDER}
zip -9rq ${ARCHIVES_FOLDER}/${RELEASE_FOLDER}.zip ./${RELEASE_FOLDER}
7zr a -bd ${ARCHIVES_FOLDER}/${RELEASE_FOLDER}.7z ./${RELEASE_FOLDER}

# Generate archive checksum files
cd ${ARCHIVES_FOLDER}
for i in tar.bz2 tar.gz zip 7z; do
  md5sum ${RELEASE_FOLDER}.${i} > ${RELEASE_FOLDER}.${i}.sum
done

cd ${CWD}

# Prepare FTP batch
printf "%b\n" "cd /home/frs/project/i/i-/i-mscp" > sftpbatch
printf "%b\n" "mkdir i-MSCP\ ${RELEASE_TAG}" >> sftpbatch
printf "%b\n" "cd i-MSCP\ ${RELEASE_TAG}" >> sftpbatch
for i in zip 7ztar.gz tar.bz2; do
  printf "%b\n" "put ${ARCHIVES_FOLDER}/${RELEASE_FOLDER}.${i}" >> sftpbatch
  printf "%b\n" "put ${ARCHIVES_FOLDER}/${RELEASE_FOLDER}.${i}.sum" >> sftpbatch
done
printf "%b\n" "quit" >> sftpbatch

if [ -z "${DRY_RUN}" ]; then
  # Upload archives and checksum files to SourceForge
  printf "%b\n" "Files will be uploaded to sourceforge.net.\nYou will be asked for your sourceforge password."
  sftp -o "batchmode no" -b ./sftpbatch ${FTP_USER},i-mscp@frs.sourceforge.net
fi

## GitHub (development)

# Variables
GIT_CHANGELOG_MSG=$(cat <<EOF
i-MSCP ChangeLog

------------------------------------------------------------------------------------------------------------------------
Git ${RELEASE_BRANCH}
------------------------------------------------------------------------------------------------------------------------

EOF
)

## Git branch update
cd ${GIT_FOLDER}
perl -i -pe 's/^i-MSCP ChangeLog/'"$GIT_CHANGELOG_MSG"'/' ./CHANGELOG
sed -i "s/\(^Version\s=\).*/\1 Git ${RELEASE_BRANCH}/" ./configs/*/imscp.conf
sed -i "s/\(^Build\s=\).*/\1/" ./configs/*/imscp.conf
sed -i "s/${RELEASE_BRANCH}/<release_branch>/g" ./docs/*/INSTALL.md
sed -i "s/${RELEASE_TAG}/<release_tag>/g" ./docs/*/INSTALL.md
sed -i "s/\(## Version ${RELEASE} (build ${RELEASE_BUILD})\)/## Version <release> (build <release_build>)\n\n\1/" ./docs/${RELEASE_BRANCH}_errata.md
git commit -a -m "Update for Git ${RELEASE_BRANCH}"
git push ${DRY_RUN} origin ${RELEASE_BRANCH}:${RELEASE_BRANCH}
