#!/bin/sh
# i-MSCP - internet Multi Server Control Panel
# Copyright (C) 2010-2014 by internet Multi Server Control Panel
#
# @author    Laurent Declercq <l.declercq@nuxwin.com>
# @link      http://i-mscp.net
#
# @license
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
#
# IMPORTANT
#
# You must have write access to the i-MSCP git repository (just import your ssh key if needed)
# Usage example: ./release.sh -b 1.1.x -r 1.1.14 -t 'username:password' -m 'Laurent Declercq' -f nuxwin -s -d

set -e

clear

CWD=$(pwd)

# Command line options
usage() {
	NAME=`basename $0`
	echo "Usage: bash $NAME -r <RELEASE> -t <TRANSIFEX_CREDENTIALS> [OPTIONS] ..."
	echo "Release new i-MSCP version on github and sourceforge"
	echo ""
	echo "Options:"
	echo "  -b  Git branch onto operate."
	echo "  -r  i-MSCP release (such as 1.1.0-rc1)."
	echo "  -t  Transifex credentials provided as 'username:password'."
	echo "  -m  Release manager name (default to Laurent Declercq)."
	echo "  -f  Sourceforge username (default to nuxwin)."
	echo "  -s  Whether or not use sudo for the restricted commands."
	echo "  -d  Do everything except actually send the updates on both Github and Sourceforge."
	echo "  -h  Show this help."

	exit 1
}

# Set default option values
RELEASEMANAGER="Laurent Declercq"
FTPUSER="nuxwin"
TRANSIFEX=""
TARGETVERSION=""
SUDO=""
DRYRUN=""
BRANCH=""

# Parse command line options
if [ "$#" -eq "1" -a "$1" = "-h" ]; then usage; fi

while getopts ":b:f:m:r:t:sd" option;
do
	case ${option} in
		b)
			BRANCH=$OPTARG
		;;
		f)
			FTPUSER=$OPTARG
		;;
		m)
			RELEASEMANAGER=$OPTARG
		;;
		r)
			TARGETVERSION=$OPTARG
		;;
		t)
			TRANSIFEX=$OPTARG
			TRANSIFEXUSER=$(echo "${TRANSIFEX}" | cut -s -d ":" -f 1 | sed 's/ //g')
			TRANSIFEXPWD=$(echo "${TRANSIFEX}" | cut -s -d ":" -f 2 | sed 's/ //g')
		;;
		s)
			SUDO="sudo"
		;;
		d)
			DRYRUN="--dry-run"
		;;
		\?)
			echo "Invalid option: -$OPTARG" >&2
			usage
			;;
		:)
			echo "Option -$OPTARG requires an argument." >&2
			usage
		;;
	esac
done


if [ -z "${BRANCH}" ]; then
	echo "-b option is missing" >&2
	usage
elif [ -z "${TARGETVERSION}" ]; then
	echo "-r option is missing" >&2
	usage
elif [ -z "${TRANSIFEX}" ]; then
	echo "-t option is missing" >&2
	usage
elif [ -z "${TRANSIFEXUSER}" ] || [ -z "${TRANSIFEXPWD}" ]; then
	echo "-t option require an username and password provided as 'username:password'" >&2
	usage
fi

# Variables
GITFOLDER="imscpgit"
GITHUBURL="git@github.com:i-MSCP/imscp.git"
BUILDFOLDER="imscp-${TARGETVERSION}"
RELEASEFOLDER="imscp-${TARGETVERSION}"
ARCHIVESFOLDER="archives"
FTPFOLDER="i-MSCP-${TARGETVERSION}"
TARGETBUILDDATE=$(date -u +"%Y%m%d")
CHANGELOGMSG="\n\n`date -u +%Y-%m-%d`: ${RELEASEMANAGER}\n\tRELEASE i-MSCP ${TARGETVERSION}"
CHANGELOGMSG2=$(cat <<EOF
i-MSCP ChangeLog

------------------------------------------------------------------------------------------------------------------------
Git ${BRANCH}
------------------------------------------------------------------------------------------------------------------------

EOF
)

########################################################################################################################
# Packages installation
########################################################################################################################

${SUDO} apt-get update && ${SUDO} apt-get install perl git-core bzip2 zip p7zip gettext python-setuptools
${SUDO} easy_install --upgrade transifex-client

########################################################################################################################
# Setup working environment
########################################################################################################################

if [ ! -d "${CWD}/${GITFOLDER}" ]; then
	# Clone repository
	git clone ${GITHUBURL} ${GITFOLDER}
fi

cd ${CWD}/${GITFOLDER}

# Cleanup current (local) branch
git checkout .
git clean -f -d

# Update remote references
git fetch

# Switch to the selected (local) branch
git checkout ${BRANCH}

# Remove any local change
while git status | grep -q "ahead"; do
	git reset --hard HEAD^
done

# Pull changes from remote repository
git pull

########################################################################################################################
# Release preparation
########################################################################################################################

sed -i -nr '1h;1!H;${;g;s/('"Git ${BRANCH}"'\n-+)/\1'"${CHANGELOGMSG}"'/g;p;}' ./CHANGELOG
sed -i "s/Git ${BRANCH}/${TARGETVERSION}/" ./CHANGELOG
sed -i "s/\(Version\s=\).*/\1 ${TARGETVERSION}/" ./configs/*/imscp.conf
sed -i "s/<version>/${TARGETVERSION}/g" ./docs/*/INSTALL
sed -i "s/\(BuildDate\s=\).*/\1 ${TARGETBUILDDATE}/" ./configs/*/imscp.conf
echo "${TARGETBUILDDATE}" > ./latest.txt

########################################################################################################################
# Translation files
########################################################################################################################

# Create transifex configuration file

if [ -f "$HOME/.transifexrc" ]; then
	rm $HOME/.transifexrc
fi

touch $HOME/.transifexrc
printf "%b\n" "[https://www.transifex.com]" >> $HOME/.transifexrc
printf "%b\n" "hostname = https://www.transifex.com" >> $HOME/.transifexrc
printf "%b\n" "password = ${TRANSIFEXPWD}" >> $HOME/.transifexrc
printf "%b\n" "token = " >> $HOME/.transifexrc
printf "%b\n" "username = ${TRANSIFEXUSER}" >> $HOME/.transifexrc

cd ${CWD}/${GITFOLDER}/i18n

# Update translation files
# This must be done prior any resource translation file update to avoid overriding of last translator names

# Pull latest translation files from Transifex ( update *.po files )
tx pull -af

cd ${CWD}/${GITFOLDER}/i18n/tools

# Compile mo files ( create *.mo files using *.po files )
sh compilePo

# Update translation resource file on transifex

# Re-create translation resource file ( iMSCP.pot ) by extracting translation strings from source
sh makemsgs

# Revert back package version to <version>
git checkout makemsgs

if [ -z "$DRYRUN" ]; then
	cd ${CWD}/${GITFOLDER}/i18n
	tx push -s
fi

cd ${CWD}/${GITFOLDER}/i18n

# Pull latest translation files from Transifex again ( update *.po files )
tx pull -af

########################################################################################################################
# Commit changes on Github
########################################################################################################################

cd ${CWD}/${GITFOLDER}

git add .
git commit -a -m "Preparation for new release: ${TARGETVERSION}"
git push origin ${BRANCH}:${BRANCH} ${DRYRUN}

# Add git tag for new release
git tag -f ${TARGETVERSION} -m "i-MSCP $TARGETVERSION release" origin/${BRANCH}
git push origin ${TARGETVERSION} ${DRYRUN}
git pull

if [ -n "$DRYRUN" ]; then
    git tag -d ${TARGETVERSION}
fi

########################################################################################################################
# Create release folder
########################################################################################################################

cd ${CWD}

rm -fr ${BUILDFOLDER}
cp -rp ${GITFOLDER} ${BUILDFOLDER}
${SUDO} rm -fr ${BUILDFOLDER}/.git

########################################################################################################################
# Git branch update
########################################################################################################################

cd ${CWD}/${GITFOLDER}

perl -i -pe 's/i-MSCP ChangeLog/'"$CHANGELOGMSG2"'/' ./CHANGELOG
sed -i "s/\(Version\s=\).*/\1 Git ${BRANCH}/" ./configs/*/imscp.conf
sed -i "s/${TARGETVERSION}/<version>/g" ./docs/*/INSTALL
sed -i "s/\(BuildDate\s=\).*/\1/" ./configs/*/imscp.conf
echo "" > ./latest.txt

########################################################################################################################
# Commit change on GitHub
########################################################################################################################

git commit -a -m "Update for Git ${BRANCH}"
git push origin ${BRANCH}:${BRANCH} ${DRYRUN}

########################################################################################################################
# Create release archives and md5sum files
########################################################################################################################

cd ${CWD}

rm -fr ${ARCHIVESFOLDER};
mkdir ${ARCHIVESFOLDER};

tar cjf ${ARCHIVESFOLDER}/${RELEASEFOLDER}.tar.bz2 ./${BUILDFOLDER}
md5sum ${ARCHIVESFOLDER}/${RELEASEFOLDER}.tar.bz2 > ./${ARCHIVESFOLDER}/${RELEASEFOLDER}.tar.bz2.sum

tar czf ${ARCHIVESFOLDER}/${RELEASEFOLDER}.tar.gz ./${BUILDFOLDER}
md5sum ${ARCHIVESFOLDER}/${RELEASEFOLDER}.tar.gz > ./${ARCHIVESFOLDER}/${RELEASEFOLDER}.tar.gz.sum

zip -9rq ${ARCHIVESFOLDER}/${RELEASEFOLDER}.zip ./${BUILDFOLDER}
md5sum ${ARCHIVESFOLDER}/${RELEASEFOLDER}.zip > ./${ARCHIVESFOLDER}/${RELEASEFOLDER}.zip.sum

7zr a -bd ${ARCHIVESFOLDER}/${RELEASEFOLDER}.7z ./${BUILDFOLDER}
md5sum ${ARCHIVESFOLDER}/${RELEASEFOLDER}.7z > ./${ARCHIVESFOLDER}/${RELEASEFOLDER}.7z.sum

########################################################################################################################
# Send file to sourceForge
########################################################################################################################

if [ -e "./ftpbatch.sh" ]; then
	rm -f ./ftpbatch.sh
fi

touch ./ftpbatch.sh

printf "%b\n" "cd /home/frs/project/i/i-/i-mscp" >> ftpbatch.sh
printf "%b\n" "mkdir i-MSCP\ ${TARGETVERSION}" >> ftpbatch.sh
printf "%b\n" "cd i-MSCP\ ${TARGETVERSION}" >> ftpbatch.sh
printf "%b\n" "put ${ARCHIVESFOLDER}/${RELEASEFOLDER}.zip" >> ftpbatch.sh
printf "%b\n" "put ${ARCHIVESFOLDER}/${RELEASEFOLDER}.zip.sum" >> ftpbatch.sh
printf "%b\n" "put ${ARCHIVESFOLDER}/${RELEASEFOLDER}.7z" >> ftpbatch.sh
printf "%b\n" "put ${ARCHIVESFOLDER}/${RELEASEFOLDER}.7z.sum" >> ftpbatch.sh
printf "%b\n" "put ${ARCHIVESFOLDER}/${RELEASEFOLDER}.tar.gz" >> ftpbatch.sh
printf "%b\n" "put ${ARCHIVESFOLDER}/${RELEASEFOLDER}.tar.gz.sum" >> ftpbatch.sh
printf "%b\n" "put ${ARCHIVESFOLDER}/${RELEASEFOLDER}.tar.bz2" >> ftpbatch.sh
printf "%b\n" "put ${ARCHIVESFOLDER}/${RELEASEFOLDER}.tar.bz2.sum" >> ftpbatch.sh
printf "%b\n" "quit" >> ftpbatch.sh

if [ -z "$DRYRUN" ]; then
	printf "%b\n" "Files will be uploaded to sourceforge.net.\nYou will be asked for your sourceforge password."
	sftp -o "batchmode no" -b ./ftpbatch.sh ${FTPUSER},i-mscp@frs.sourceforge.net
fi

exit
