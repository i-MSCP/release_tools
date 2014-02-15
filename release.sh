#!/bin/sh
# i-MSCP - internet Multi Server Control Panel
# Copyright (C) 2010-2013 by internet Multi Server Control Panel
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
# Usage example: ./release.sh -b stable -r 1.1.1 -t 'username:password' -m 'Laurent Declercq' -f nuxwin -s -d
#
# Will in order:
#  - Clone the i-MSCP git repository or pull changes from it if already there
#  - Switch to the specified branch if needed
#  - Prepare the release by updating version and builddate in all files
#  - Push the iMSCP.pot file on Transifex
#  - Pull all *.po files from Transifex
#  - Update the CHANGELOG to add release info (date, release manager name and version)
#  - Commit all changes on the remote i-MSCP git repository
#  - Create a git tag for the new release on the remote i-MSCP git repository
#  - Create all archives to upload on Sourceforge
#  - Upload all archives on Sourceforge
#
# Script tested with Bash and Dash.
#

set -e

clear

# Command line options

usage() {
	NAME=`basename $0`
	echo "Usage: bash $NAME -r <RELEASE> -t <TRANSIFEX_CREDENTIALS> [OPTIONS]"
	echo "Release new i-MSCP version on github and sourceforge"
	echo ""
	echo "Options:"
	echo "  -b  Git branch onto operate (default to stable)."
	echo "  -r  i-MSCP release (such as 1.1.0-rc1)."
	echo "  -t  Transifex credentials provided as 'username:password'."
	echo "  -m  Release manager name (default to Torsten Widmann)."
	echo "  -f  Sourceforge username (default to goover)."
	echo "  -s  Whether or not use sudo for the restricted commands."
	echo "  -d  Do everything except actually send the updates on both Github and Sourceforge."
	echo "  -h  Show this help."

	exit 1
}

# Set default option values
RELEASEMANAGER="Laurent Declercq"
FTPUSER=""
TRANSIFEX=""
TARGETVERSION=""
SUDO=""
DRYRUN=""
BRANCH="stable"

# Parse options
if [ "$#" -eq "1" -a "$1" = "-h" ]; then usage; fi

while getopts "b:f:m:r:t:sd" option;
do
	case $option in
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

if [ -z "${TARGETVERSION}" ]; then
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
IMSCPCONF="configs/debian/imscp.conf"
GITFOLDER="imscpgit"
GITHUBURL="git@github.com:i-MSCP/imscp.git"
BUILDFOLDER="imscp-${TARGETVERSION}"
RELEASEFOLDER="imscp-${TARGETVERSION}"
ARCHIVESFOLDER="archives"
FTPFOLDER="i-MSCP-${TARGETVERSION}"
CHANGELOGMSG="\n\n`date -u +%Y-%m-%d`: ${RELEASEMANAGER}\n\t- RELEASE i-MSCP ${TARGETVERSION}"
CHANGELOGMSG2=$(cat <<EOF
~~~~~~~~~~~~~~~~

------------------------------------------------------------------------------------------------------------------------
Git ${BRANCH}
------------------------------------------------------------------------------------------------------------------------

Tickets:
EOF
)

echo ""
echo "NEW RELEASE ${TARGETVERSION} WILL BE CREATED FROM ${BRANCH} BRANCH. THIS CAN TAKE SOME TIME. PLEASE WAIT..."
echo ""

$SUDO aptitude update
$SUDO aptitude install perl-base git-core bzip2 zip p7zip gettext python-setuptools
$SUDO easy_install --upgrade transifex-client

if [ ! -d "./${GITFOLDER}" ]; then
	echo "Cloning i-MSCP repository..."
	git clone -b ${BRANCH} ${GITHUBURL} ${GITFOLDER}
	cd ${GITFOLDER}
else
	echo "Pull changes from github..."
	cd ${GITFOLDER}
	git pull
	git checkout ${BRANCH}

	# Cleanup
	git checkout .
	git clean -f -d

	while git status | grep -q "ahead"; do
		git reset --hard HEAD^
	done
fi

echo ""
echo "RELEASE PREPARATION"
echo ""

# Build Date
CURRENTBUILDDATE=$(grep '^BuildDate =' $IMSCPCONF | cut -d "=" -f 2 | sed 's/ //g')
TARGETBUILDDATE=$(date -u +"%Y%m%d")

echo "Updating CHANGELOG file..."
sed -i -nr '1h;1!H;${;g;s/('"Git ${BRANCH}"'\n-+)/\1'"${CHANGELOGMSG}"'/g;p;}' ./CHANGELOG
sed -i "s/Git ${BRANCH}/${TARGETVERSION}/" ./CHANGELOG

echo "Updating version in imscp.conf and INSTALL files..."
sed -i "s/Version\s=.*/Version = ${TARGETVERSION}/" configs/*/imscp.conf
sed -i "s/<verion>/${TARGETVERSION}/g" ./docs/*/INSTALL

echo "Updating BuildDate in imscp.conf and latest.txt files..."
sed -i "s/${CURRENTBUILDDATE}/${TARGETBUILDDATE}/" configs/*/imscp.conf
sed -i "s/${CURRENTBUILDDATE}/${TARGETBUILDDATE}/" ./latest.txt

echo ""
echo "UPDATING TRANSLATION FILES"
echo ""

echo "Creating $HOME/.transifexrc file..."

if [ -e "$HOME/.transifexrc" ]; then
	rm -rf $HOME/.transifexrc
fi

touch $HOME/.transifexrc

printf "%b\n" "[https://www.transifex.com]" >> $HOME/.transifexrc
printf "%b\n" "hostname = https://www.transifex.com" >> $HOME/.transifexrc
printf "%b\n" "password = ${TRANSIFEXPWD}" >> $HOME/.transifexrc
printf "%b\n" "token = " >> $HOME/.transifexrc
printf "%b\n" "username = ${TRANSIFEXUSER}" >> $HOME/.transifexrc

echo "Updating portable object template file with new translation strings..."
cd i18n/tools
sh makemsgs

echo "Pushing new portable object template file on Transifex..."
cd ..

if [ -z "$DRYRUN" ]; then
    tx push -s
fi

echo "Getting last available portable object files from Transifex..."
tx pull -af

echo "Compiling object machines files..."
cd tools
sh compilePo

cd ../..

echo ""
echo "COMMIT CHANGES TO GITHUB"
echo ""

git add .
git commit -m "Preparation for release: ${TARGETVERSION}"
git push origin ${BRANCH}:${BRANCH} $DRYRUN

echo "New git tag $TARGETVERSION for the i-MSCP $TARGETVERSION release will be added on github";

git tag -f ${TARGETVERSION} -m "i-MSCP $TARGETVERSION release" origin/${BRANCH}
git push origin ${TARGETVERSION} $DRYRUN
git pull

if [ -z "$DRYRUN" ]; then
    git tag -d ${TARGETVERSION}
fi

echo ""
echo "GIT BRANCH PREPARATION"
echo ""

echo "Updating CHANGELOG file..."
perl -i -pe 's/~+/'"$CHANGELOGMSG2"'/' ./CHANGELOG

echo "Updating version in imscp.conf and INSTALL files..."
sed -i "s/Version\s=.*/Version = Git ${BRANCH}/" configs/*/imscp.conf
sed -i "s/${TARGETVERSION}/<verion>/g" ./docs/*/INSTALL

git add .
git commit -m "Update for Git ${BRANCH}"
git push origin ${BRANCH}:${BRANCH} $DRYRUN

cd ..

echo ""
echo "CREATING ARCHIVES TO UPLOAD ON SOURCEFORGE"
echo ""

echo "Creating release folder"
rm -fr $BUILDFOLDER
cp -r $GITFOLDER $BUILDFOLDER
$SUDO rm -fr $BUILDFOLDER/.git

echo "Creating archives folder"
rm -fr $ARCHIVESFOLDER;
mkdir $ARCHIVESFOLDER;

echo "Creating ${ARCHIVESFOLDER}/$RELEASEFOLDER.tar.bz2 archive..."
tar cjf ${ARCHIVESFOLDER}/${RELEASEFOLDER}.tar.bz2 ./$BUILDFOLDER
md5sum ${ARCHIVESFOLDER}/${RELEASEFOLDER}.tar.bz2 > ./${ARCHIVESFOLDER}/${RELEASEFOLDER}.tar.bz2.sum

echo "Creating ${ARCHIVESFOLDER}/$RELEASEFOLDER.tar.gz archive..."
tar czf ${ARCHIVESFOLDER}/${RELEASEFOLDER}.tar.gz ./$BUILDFOLDER
md5sum ${ARCHIVESFOLDER}/${RELEASEFOLDER}.tar.gz > ./${ARCHIVESFOLDER}/${RELEASEFOLDER}.tar.gz.sum

echo "Creating ${ARCHIVESFOLDER}/$RELEASEFOLDER.zip archive..."
zip -9rq ${ARCHIVESFOLDER}/${RELEASEFOLDER}.zip ./$BUILDFOLDER
md5sum ${ARCHIVESFOLDER}/${RELEASEFOLDER}.zip > ./${ARCHIVESFOLDER}/${RELEASEFOLDER}.zip.sum

echo "Creating ${ARCHIVESFOLDER}/$RELEASEFOLDER.7z archive..."
7zr a -bd ${ARCHIVESFOLDER}/${RELEASEFOLDER}.7z ./$BUILDFOLDER
md5sum ${ARCHIVESFOLDER}/${RELEASEFOLDER}.7z > ./${ARCHIVESFOLDER}/${RELEASEFOLDER}.7z.sum

echo ""
echo "UPLOADING ARCHIVES TO SOURCEFORGE"
echo ""

echo "Creating ftp batch file..."

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
