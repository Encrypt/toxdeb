#!/bin/bash

# ToxDeb - The Tox Client Debianizer
# A BASH script to build Tox Clients for Debian
#
# Copyright (C) 2016 Yann Privé
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later
# version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
# details.
#
# You should have received a copy of the GNU General Public License along with
# this program. If not, see http://www.gnu.org/licenses/.

# Gets the execution parameters
readonly PROGNAME=$(basename $0)
readonly ARGS=("$@")
readonly ARGS_NB=$#

# Configuration of the script
readonly PROGRAM_NAME='uTox'
readonly MAIN_FILE='main.h'

readonly GIT_REPO='https://github.com/GrayHatter/uTox.git'
readonly HTTP_REPO='https://github.com/grayhatter/utox'
readonly BUILD_BRANCH='master'

readonly MAINT_NAME='Yann Prive'
readonly MAINT_EMAIL='encrypt@encrypt-tips.tk'

readonly COPYRIGHT_YEARS="2014-$(date '+%Y')"
readonly COPYRIGHT_WEBSITE='http://utox.org'
readonly COPYRIGHT_ORGANISATION='cmdline <http://cmdline.org>'

readonly DESC_SHORT='Tox client'
readonly DESC_LONG='The lightest and fluffiest Tox client.'
readonly BUILD_DEPENDENCIES='debhelper (>= 9), libopus-dev, libvpx-dev, libfontconfig1-dev, libdbus-1-dev, libv4l-dev, libxrender-dev, libopenal-dev, libxext-dev, libtoxcore-dev, libfilteraudio-dev, libtoxav-dev, libtoxencryptsave-dev, libtoxdns-dev'
readonly BUILD_TARGETS=('jessie')

# Main function 
main() {

	# Local variables
	local client_version

	# Download and correctly present the source code
	get_source
	
	# Gets the version of teh client
	client_version=$(get_version)
	
	# Prepare the source folder
	prepare_source "${client_version}"
	
	# Build the Tox client with pbuilder
	build_client "${client_version}"
	
	return 0
	
}

# Get the source code from github
get_source() {

	# Clean the previous version of the program built
	rm -rf $(find . -maxdepth 1 -name "${PROGRAM_NAME,,}[-_][0-9]*")
	
	# If the code has already been cloned, update
	if [[ -d "${PROGRAM_NAME,,}_src" ]]
	then
		cd "${PROGRAM_NAME,,}_src"
		git checkout "${BUILD_BRANCH}"
		git pull
	
	# Else, download it from the git repo
	else
		git clone "${GIT_REPO}" "${PROGRAM_NAME,,}_src"
		cd "${PROGRAM_NAME,,}_src"
		git checkout "${BUILD_BRANCH}"
	fi
	
	# Bach to parent directory
	cd ..
}

# Gets the version of µTox
get_version() {

	# Local variables
	local main_headers

	# Get the "main" headers in the folder
	main_headers=($(find ${CLONE_FOLDER} -name "${MAIN_FILE}"))
	
	# Return the version
	echo $(grep VERSION ${main_headers[@]} | grep -oE '([0-9]{1,}\.)+[0-9]{1,}')
	
}


# Prepare the source for pbuilder, generating a .dsc file
prepare_source() {

	# Local variables
	local client_version="$1"
	local parent_folder

	# Correctly rename the source folder (becoming the parent folder)
	parent_folder="${PROGRAM_NAME,,}-${client_version}"
	cp -r "${PROGRAM_NAME,,}_src" "${parent_folder}"
	
	# Convert the source as a .tar.gz archive
	tar -zcvf "${parent_folder}.tar.gz" "${parent_folder}"
	
	# Invoke dh_make to prepare the source
	export DEBFULLNAME="${MAINT_NAME}"
	export DEBEMAIL="${MAINT_EMAIL}"
	
	cd ${parent_folder}
	dh_make -s -y -c gpl3 -f "../${parent_folder}.tar.gz"
	
	# Cleaning of the debian/ directory
	rm debian/{*.ex,*.EX,docs,README.*}
	
	# Complete the control file
	sed -i "s/Section:.*/Section: net/g" debian/control
	sed -i "s/Build-Depends:.*/Build-Depends: ${BUILD_DEPENDENCIES}/g" debian/control
	sed -i "s,Homepage:.*,Homepage: ${COPYRIGHT_WEBSITE},g" debian/control
	sed -i "s,#Vcs-Git:.*,Vcs-Git: ${GIT_REPO},g" debian/control
	sed -i "s,#Vcs-Browser:.*,Vcs-Browser: ${HTTP_REPO},g" debian/control
	sed -i "s/<insert up to 60 chars description>/${DESC_SHORT}/g" debian/control
	sed -i "s/<insert long description, indented with spaces>/${DESC_LONG}/g" debian/control
	
	# Correctly set-up the copyright info
	sed -i "s/<years>/${COPYRIGHT_YEARS}/g" debian/copyright
	sed -i "s,<put author's name and email here>,${COPYRIGHT_ORGANISATION},g" debian/copyright
	sed -i "s,<url://example.com>,${COPYRIGHT_WEBSITE},g;" debian/copyright
	sed -i '/#/d;/<likewise for another author>/d' debian/copyright
	
	# Add the manpage
	cp $(find . -name ${PROGRAM_NAME,,}.1) debian/
	
	# Set the menu file
	cat <<- EOF > debian/menu
	?package(${PROGRAM_NAME,,}):needs="X11" \\
	 section="Applications/Network/Communication" \\
	 title="${PROGRAM_NAME}" command="/usr/bin/${PROGRAM_NAME,,}"
	EOF
	
	# Override dh_usrlocal which complains
	# TODO: To remove and set the proper path for the installation of utox
	echo 'override_dh_usrlocal:' >> debian/rules
	
	# Get the changelog from the author
	echo 'YOUR INPUT IS NEEDED!'
	echo "Please enter the changelog for this version of ${PROGRAM_NAME}"
	read -p 'Press enter to edit... '
	dch -e
	
	# Call debuild to generate the .dsc file
	debuild -S --lintian-opts -i -sa
	
}

# Build the Tox client with pbuilder
build_client() {

	# Local variables
	local target
	
	# Goes back to the parent directory
	cd ..

	# For each target, build the client
	for target in ${BUILD_TARGETS[@]}
	do
	
		# Launches the building process
		# TODO: To modify
		pbuilder --build --basetgz "/var/cache/pbuilder/${target}-amd64.tgz" *.dsc
	
	done
}

# Launch the main function
main

# Exit with the correct exit code
exit $?
