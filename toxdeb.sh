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
readonly CLIENT_NAME='uTox'
readonly MAIN_FILE='main.h'

readonly GIT_REPO='https://github.com/GrayHatter/uTox.git'
readonly HTTP_REPO='https://github.com/grayhatter/utox'
readonly BUILD_BRANCH='master'

readonly MAINT_NAME='Yann Prive'
readonly MAINT_EMAIL='encrypt@encrypt-tips.tk'

readonly COPYRIGHT_YEARS="2014-$(date '+%Y')"
readonly COPYRIGHT_WEBSITE='http://utox.org'
readonly COPYRIGHT_ORGANISATION='cmdline <http://cmdline.org>'

readonly SECTION_TYPE='net'
readonly DESC_SHORT='Tox client'
readonly DESC_LONG='The lightest and fluffiest Tox client.'
readonly BUILD_DEPENDENCIES='debhelper (>= 9), libvpx-dev, libfontconfig1-dev, libdbus-1-dev, libv4l-dev, libxrender-dev, libopenal-dev, libxext-dev, libtoxcore-dev, libfilteraudio-dev, libtoxav-dev, libtoxencryptsave-dev, libtoxdns-dev'

readonly TARGET_DISTS=('jessie')
readonly TARGET_ARCHS=('amd64')

# Main function 
main() {
	
	# Local variables
	local client_version
	local entry
	
	# Checks the number of arguments before going forward
	if [[ ${ARGS_NB} -lt 1 ]]
	then
		error 'arguments_number'
		return $?
	fi
	
	# Gets the option given
	case ${ARGS[0]} in
		
		# Prepare the source and generate the .dsc file
		--prepare-source)
		
			# Warn if this is run as root
			[[ $(id -u) -eq 0 ]] && echo "WARNING: You shouldn't run ./${PROGNAME} ${ARGS[0]} with root privileges." >&2
			
			# Get the source and generate the .dsc
			get_source
			client_version=$(get_version)
			prepare_source "${client_version}"
			
			# Instructions for the next step
			echo 'The sources are ready to be built.'
			echo "Run ./${PROGNAME} --build as root to build ${CLIENT_NAME}."
			;;
			
		# Build the clients with pbuilder
		--build)
		
			# Build should be run as root
			[[ $(id -u) -ne 0 ]] && { error 'root_privileges' '--build' ; return $? ; }
			
			# Gets the version
			client_version=$(get_version)
			
			# Asks user to validate changes
			echo "On the way to build ${CLIENT_NAME} ${client_version}!"
			echo "Target version(s): ${TARGET_DISTS[@]}"
			echo "Target architecture(s): ${TARGET_ARCHS[@]}"
			read -p "Is this OK? [Y/n] " entry
			case $entry in
				Y)
					build_client "${client_version}"
					;;
				n)
					echo 'Abort.'
					return 0
					;;
				*)
					error 'incorrect_entry' "$entry"
					;;
			esac
			;;
		
		# Setup the pbuilder configuration
		--setup-pbuilder)
			setup_builder
			;;
		
		# Displays the help
		--help)
			help
			;;
		
		# Well... at least you tried :P
		*)
			error 'unknown option' "${ARGS[0]}"
			;;
	esac
	
	# Return the correct exit code
	return $?
}

# Get the source code from github
get_source() {
	
	# If the code has already been cloned, update
	if [[ -d "${CLIENT_NAME,,}_src" ]]
	then
		cd "${CLIENT_NAME,,}_src"
		git checkout "${BUILD_BRANCH}"
		git pull
	
	# Else, download it from the git repo
	else
		git clone "${GIT_REPO}" "${CLIENT_NAME,,}_src"
		cd "${CLIENT_NAME,,}_src"
		git checkout "${BUILD_BRANCH}"
	fi
	
	# Back to parent directory
	cd ..
	
	return 0
}

# Gets the version of µTox
get_version() {

	# Local variables
	local main_headers

	# Get the "main" headers in the folder
	main_headers=($(find "${CLIENT_NAME,,}_src" -name "${MAIN_FILE}"))
	
	# Return the version
	echo $(grep VERSION ${main_headers[@]} | grep -oE '([0-9]{1,}\.)+[0-9]{1,}')	
	
	return 0
}


# Prepare the source for pbuilder, generating a .dsc file
prepare_source() {

	# Local variables
	local client_version="$1"
	local parent_folder
	
	# Clean the previous version of the program built if there is any
	rm -rf $(find . -maxdepth 1 -name "${CLIENT_NAME,,}[-_][0-9]*")
	
	# Correctly rename the source folder (becoming the parent folder)
	parent_folder="${CLIENT_NAME,,}-${client_version}"
	cp -r "${CLIENT_NAME,,}_src" "${parent_folder}"
	
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
	sed -e "s/Section:.*/Section: ${SECTION_TYPE}/g" \
		-e "s/Build-Depends:.*/Build-Depends: ${BUILD_DEPENDENCIES}/g" \
		-e "s,Homepage:.*,Homepage: ${COPYRIGHT_WEBSITE},g" \
		-e "s,#Vcs-Git:.*,Vcs-Git: ${GIT_REPO},g" \
		-e "s,#Vcs-Browser:.*,Vcs-Browser: ${HTTP_REPO},g" \
		-e "s/<insert up to 60 chars description>/${DESC_SHORT}/g" \
		-e "s/<insert long description, indented with spaces>/${DESC_LONG}/g" \
		-i debian/control
	
	# Correctly set-up the copyright info
	sed -e "s/<years>/${COPYRIGHT_YEARS}/g" \
		-e "s,<put author's name and email here>,${COPYRIGHT_ORGANISATION},g" \
		-e "s,<url://example.com>,${COPYRIGHT_WEBSITE},g" \
		-e '/#/d;/<likewise for another author>/d' \
		-i debian/copyright
	
	# Add the manpage
	cp $(find . -name ${CLIENT_NAME,,}.1) debian/
	
	# Set the menu file
	cat <<- EOF > debian/menu
	?package(${CLIENT_NAME,,}):needs="X11" \\
	 section="Applications/Network/Communication" \\
	 title="${CLIENT_NAME}" command="/usr/bin/${CLIENT_NAME,,}"
	EOF
	
	# Set the destination prefix as /
	echo -e 'override_dh_auto_install:\n\tdh_auto_install -- PREFIX=/usr' >> debian/rules
	
	# Set the distribution as UNRELEASED at first
	sed -i '1s/unstable/UNRELEASED/g' debian/changelog
	
	# Get the changelog from the author
	echo 'YOUR INPUT IS NEEDED!'
	echo "Please enter the changelog for this version of ${CLIENT_NAME}"
	read -p 'Press enter to edit... '
	dch -e
	
	return 0
}

# Build the Tox client with pbuilder
build_client() {

	# Local variables
	local client_version=$1
	local architecture target
	local previous_target='UNRELEASED'
	
	# For each architecture
	for architecture in ${TARGET_ARCHS[@]}
	do
	
		# For each target
		for target in ${TARGET_DISTS[@]}
		do
	
			# Clean the previously generated .dsc file
			rm -rf *.dsc *.tar.xz *.build *.changes
		
			# Go to the child directory to setup the version
			cd "${CLIENT_NAME,,}-${client_version}"
		
			# Change the distribution et keeps the target
			sed -i "1s/${previous_target}/${target}/g" debian/changelog
			previous_target="${target}"
			
			# Call debuild to generate the .dsc file
			debuild -S --lintian-opts -i -sa
		
			# Go to the parent directory to call pbuilder
			cd ..
			pbuilder --build --basetgz "/var/cache/pbuilder/${target}-${architecture}.tgz" *.dsc
			[[ $? -ne 0 ]] && { error 'pbuilder_failed' ; return $?; }
			
			# Saves the result in a folder
			mkdir "${CLIENT_NAME,,}_build_v${client_version}_${target}_${architecture}"
			mv /var/cache/pbuilder/result/* "${CLIENT_NAME,,}_build_v${client_version}_${target}_${architecture}"
		
		done
		
	done
	
	# Final cleanup
	rm -rf $(find . -maxdepth 1 -name "${CLIENT_NAME,,}[-_][0-9]*")
	
	return 0
}

# Setup the pbuilder configuration
setup_pbuilder() {

	# TODO
	return 0
}

# Error handling
error() {

	local err=$1

	# Displays the error
	echo -n 'ERROR: ' >&2
	case $err in
		arguments_number)
			echo "${PROGNAME} only expects 1 argument." >&2
			echo 'Use --help to get further help.' >&2
			;;
		unknown_option)
			echo "Unknown option $2." >&2
			;;
		root_privileges)
			echo "${PROGNAME} requires root privileges to run the option $2." >&2
			;;
		incorrect_entry)
			echo "Incorrect entry: $2. Abort." >&2
			;;
		pbuilder_failed)
			echo "Pbuilder failed. Consult the logs for more information." >&2
			;;
		*)
			echo "Unrecognized error: $err." >&2
			;;
	esac

	return 1	
}

# Help about the script
help() {

	cat <<- EOF
	Usage: ${PROGNAME} [ prepare <options> | build ]
	
	Operations:
	  prepare: Gets the latest sources of the repository "GIT_REPO" and prepares the .dsc file.
	  build: Uses pbuilder to build the Tox client from the .dsc file given.
	
	Options of "prepare":
	  --architecture: Sets the target architecture.
	  --distribution: Sets the target distribution.
	
	Note that "prepare" should be run as an unpriviledged user, whereas "build" should be run as root.
	One will probably run: ./${PROGNAME} prepare --distribution jessie --architecture amd64 && sudo ./${PROGNAME} build
	
	Please make sure that the configuration is correct before running this tool.
	EOF

	return 0
}

# Launch the main function
main

# Exit with the correct exit code
exit $?
