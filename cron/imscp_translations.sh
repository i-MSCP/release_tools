#!/bin/sh

# Script that update i-MSCP translation resource files on both Transifex and Github
#
# Setup (Debian/Ubuntu):
# 1. Install needed packages and tools
#	# aptitude update && aptitude install perl git-core gettext python-setuptools openssh-client expect
#	# easy_install --upgrade transifex-client
# 2. Create dedicated unix user
#	# adduser imscp-bot
# 3 Create SSH key for GitHub (it is recommended to create dedicated github user)
#	# su imscp-bot
#	$ ssh-keygen -t rsa -C "imscp-bot@i-mscp.net"
# 4 Starting keychain
#	$ keychain --clear $HOME/.ssh/id_rsa
# 5. Copy past the pubkey and register it into GitHub
# 6. Install this script under the imscp-bot homedir (Don't forget to chmod it to 0750)
# 7. Add cron task
# 	$ crontab -e
#	>> @weekly sh $HOME/imscp_translations.sh > $HOME/imscp_translations.log 2>&1

set -e
set -u

# Configuration variables
GITFOLDER="$HOME/repositories/imscp"
GITHUBURL="git@github.com:i-MSCP/imscp.git"
TRANSIFEXUSER=""
TRANSIFEXPWD=""
SSHPASSPHASE=""

# Load keychain variable and check for id_rsa
[ -z "$HOSTNAME" ] && HOSTNAME=`uname -n`
. $HOME/.keychain/$HOSTNAME-sh 2>/dev/null
ssh-add -l 2>/dev/null | grep -q id_dsa || exit 1

# Create transifexrc file if needed
if [ ! -f "$HOME/.transifexrc" ]; then
	touch $HOME/.transifexrc
	printf "%b\n" "[https://www.transifex.com]" >> $HOME/.transifexrc
	printf "%b\n" "hostname = https://www.transifex.com" >> $HOME/.transifexrc
	printf "%b\n" "password = ${TRANSIFEXPWD}" >> $HOME/.transifexrc
	printf "%b\n" "token = " >> $HOME/.transifexrc
	printf "%b\n" "username = ${TRANSIFEXUSER}" >> $HOME/.transifexrc
fi

# Clone i-MSCP Repository if needed
if [ ! -d "${GITFOLDER}" ]; then
	mkdir -p ${GITFOLDER}
	cd ${GITFOLDER}
	git clone ${GITHUBURL} ${GITFOLDER}
fi

cd ${GITFOLDER}

# For each branch found in i-MSCP repository
for BRANCH in $(git for-each-ref --format='%(refname:short)' refs/remotes); do
	BRANCH=$(echo "${BRANCH}" | sed 's/^.*\///g')

	if [ "$BRANCH" != "HEAD" ]; then
		echo "Processing ${BRANCH} branch..."

		# Cleanup current branch
		git checkout .
		git clean -f -d

		# Checkout branch
		git checkout ${BRANCH}

		while git status | grep -q "ahead"; do
			git reset --hard HEAD^
		done

		# Pull changes
		git pull

		if [ -d "${GITFOLDER}/i18n/.tx" ]; then
			cd ${GITFOLDER}/i18n/tools

			# Create new translation resource file
			sh makemsgs

			# Upload new translation resource file (only if needed)
			STAMP="$(git diff --numstat ../iMSCP.pot | cut -f 1)"
			if [ -n $STAMP ] && [ $STAMP -gt 1 ]; then
				echo "Updating translation resource file on both Transifex and Github"
				# Upload new resource translation file on Transifex
				tx push -s

			 	# Upload new resource translation file on GitHub
				#RTFID=$(echo ${BRANCH} | sed '/./_/g');
				#cd ${GITFOLDER}
				#git add .
				#git commit -a -m "Cron task: Updated ${RTFID} translation resource file"
				#git push origin ${BRANCH}:${BRANCH}
			else
				echo "Translation resource file is already up-to-date"
				git checkout ../iMSCP.pot
			fi
		fi
	fi

	cd ${GITFOLDER}
done
