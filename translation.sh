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
# Usage example: ./translation.sh -b 1.2.x -t 'username:password' -d

set -e

clear

CWD=$(pwd)

# Command line options
usage() {
	NAME=`basename $0`
	echo "Usage: bash $NAME -b <BRANCH> -t <TRANSIFEX_CREDENTIALS> [OPTIONS] ..."
	echo "Release new i-MSCP version on github and sourceforge"
	echo ""
	echo "Options:"
	echo "  -b  Git branch onto operate."
	echo "  -t  Transifex credentials provided as 'username:password'."
	echo "  -s  Whether or not use sudo for the restricted commands."
	echo "  -d  Do everything except actually send the updates on both Transifex and Github."
	echo "  -h  Show this help."

	exit 1
}

# Set default option values
RELEASEMANAGER="Laurent Declercq"
TRANSIFEX=""
SUDO=""
DRYRUN=""
BRANCH=""

# Parse command line options
if [ "$#" -eq "1" -a "$1" = "-h" ]; then usage; fi

while getopts ":b:t:sd" option;
do
	case ${option} in
		b)
			BRANCH=$OPTARG
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

########################################################################################################################
# Packages installation
########################################################################################################################

${SUDO} apt-get update && ${SUDO} apt-get install perl git-core gettext python-setuptools
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

#
## Update translation files
## This must be done prior any resource translation file update to avoid overriding of last translator names
#

# Pull latest translation files from Transifex ( update *.po files )
tx pull -af

cd ${CWD}/${GITFOLDER}/i18n/tools

# Compile mo files ( create *.mo files using *.po files )
sh compilePo

#
## Update translation resource file on Transifex
#

# Re-create translation resource file ( iMSCP.pot ) by extracting translation strings from source
sh makemsgs

if [ -z "$DRYRUN" ]; then
	# Push new translation resource file on transifex
	cd ${CWD}/${GITFOLDER}/i18n
	tx push -s
fi

cd ${CWD}/${GITFOLDER}/i18n

# Pull latest translation files from Transifex again ( update *.po files )
tx pull -af

########################################################################################################################
# Commit changes on Github
########################################################################################################################

if [ -z "$DRYRUN" ]; then
	cd ${CWD}/${GITFOLDER}
	git add .
	git commit -a -m "Updated: Translation files ( synced with Transifex )"
	git push origin ${BRANCH}:${BRANCH} ${DRYRUN}
fi

exit
