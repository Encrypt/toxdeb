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

# Main function 
main() {
	
	# Local variables
	local client_version conf_file
	local i distribution architecture
	
	# Check the number of arguments before going forward
	[[ ${ARGS_NB} -lt 1 ]] && { error 'argument_missing' ; return $? ; }
	
	# Get the command given
	case ${ARGS[0]} in
		
		# Prepare the source and generate the .dsc file
		prepare)
		
			# Check the number of arguments before going forward
			[[ ${ARGS_NB} -ne 7 ]] && { error 'prepare_options' ; return $? ; }
			
			# Get the arguments
			for i in 1 3 5
			do
				case ${ARGS[$i]} in
					--conf)
						conf_file=${ARGS[$(($i + 1))]}
						;;
					--dist)
						distribution=${ARGS[$(($i + 1))]}
						;;
					--arch)
						architecture=${ARGS[$(($i + 1))]}
						;;
					*)
						error unknown_option "${ARGS[$i]}"
						return $?
						;;
				esac
			done
			
			# Source the configuration file exists
			[[ -e ${conf_file} ]] \
				&& source ${conf_file} \
				|| { error 'conf_file' "${conf_file}" ; return $? ; }
			
			# Warn if this is run as root
			[[ $(id -u) -eq 0 ]] && echo "WARNING: You shouldn't run ./${PROGNAME} ${ARGS[0]} with root privileges."
			
			# Get the source and generate the .dsc
			get_source
			client_version=$(get_version)
			prepare_source "$client_version" "$distribution"
			
			# Save the configuration for the next step
			cat <<- EOF > .toxdeb_prepared
			version=${client_version}
			configuration=${conf_file}
			distribution=${distribution}
			architecture=${architecture}
			EOF
			
			# Instructions for the next step
			echo 'INFO: The sources are ready to be built.'
			echo "INFO: Run ./${PROGNAME} build as root to build ${CLIENT_NAME}."
			;;
			
		# Build the clients with pbuilder
		build)
		
			# Check the number of arguments before going forward
			[[ ${ARGS_NB} -ne 1 ]] && { error 'build_options' ; return $? ; }
			
			# Build should be run as root
			[[ $(id -u) -ne 0 ]] && { error 'build_root' ; return $? ; }
			
			# Gets the parameters previously configured
			client_version=$(grep 'version' .toxdeb_prepared | sed 's/version=//')
			conf_file=$(grep 'configuration' .toxdeb_prepared | sed 's/configuration=//')
			distribution=$(grep 'distribution' .toxdeb_prepared | sed 's/distribution=//')
			architecture=$(grep 'architecture' .toxdeb_prepared | sed 's/architecture=//')
			
			# Source the configuration file
			source ${conf_file}
			
			# Check if the pbuilder chroot exists...
			[[ -e "/var/cache/pbuilder/${distribution}-${architecture}.tgz" ]] \
				|| { error 'chroot_nonexistent' "$distribution" "$architecture" ; return $? ; }
			
			# Info
			echo "INFO: Now building ${CLIENT_NAME} ${client_version}!"
			echo "INFO: Distribution: $distribution / Architecture: $architecture"
			
			# Launch the build process
			build_client "$client_version" "$distribution" "$architecture"
			
			# Remove the save file
			rm .toxdeb_prepared
			;;
			
		# Displays the help
		help)
			help
			;;
		
		# Well... at least you tried :P
		*)
			error 'unknown_operation' "${ARGS[0]}"
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
	local version_files

	# Get the "main" headers in the folder
	version_files=($(find "${CLIENT_NAME,,}_src" -name "${VERSION_FILE}"))
	
	# Return the version
	echo $(grep VERSION ${version_files[@]} | grep -oE '([0-9]{1,}\.)+[0-9]{1,}')
	
	return 0
}

# Prepare the source for pbuilder, generating a .dsc file
prepare_source() {

	# Local variables
	local client_version=$1
	local distribution=$2
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
	
	# Set the distribution
	sed -i "1s/unstable/${distribution}/g" debian/changelog
	
	# Get the changelog from the author
	echo 'YOUR INPUT IS NEEDED!'
	echo "Please enter the changelog for this version of ${CLIENT_NAME}"
	read -p 'Press enter to edit... '
	dch -e
	
	# Call dpkg-source to generate the .dsc file
	dpkg-source -b .
	
	# Back to the parent directory
	cd ..
	
	return 0
}

# Build the Tox client with pbuilder
build_client() {

	# Local variables
	local client_version=$1
	local distribution=$2
	local architecture=$3
	
	# Call pbuilder
	pbuilder --build --basetgz "/var/cache/pbuilder/${distribution}-${architecture}.tgz" *.dsc
	[[ $? -ne 0 ]] && { error 'pbuilder_failed' ; return $?; }
	
	# Save the result in a folder
	mkdir "${CLIENT_NAME,,}_build_v${client_version}_${target}_${architecture}"
	mv /var/cache/pbuilder/result/* "${CLIENT_NAME,,}_build_v${client_version}_${target}_${architecture}"
	
	# Final cleanup
	rm -rf $(find . -maxdepth 1 -name "${CLIENT_NAME,,}[-_][0-9]*")
	
	return 0
}

# Error handling
error() {

	local err=$1

	# Displays the error
	echo -n 'ERROR: ' >&2
	case $err in
		argument_missing)
			echo "${PROGNAME} expects at least one argument." >&2
			echo "Use \"${PROGNAME} help\" to get further help." >&2
			;;
		conf_file)
			echo "The configuration file ($2) given has argument doesn't exist." >&2
			;;
		prepare_options)
			echo 'The operation "prepare" expects 3 options with their respective values.' >&2
			echo "Use \"${PROGNAME} help\" to get further help." >&2
			;;
		build_options)
			echo 'The operation "build" does not expect any argument.' >&2
			;;
		unknown_option)
			echo "Unknown option $2 for operation \"prepare\"." >&2
			;;
		chroot_nonexistent)
			echo "Nonexistent base .tgz for distribution $2 and architecture $3!" >&2
			;;
		unknown_operation)
			echo "Unknown operation $2." >&2
			;;
		build_root)
			echo "${PROGNAME} requires root privileges to run the operation \"build\"." >&2
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
	Usage: ${PROGNAME} [ prepare <options> | build | help ]
	
	Operations:
	  prepare: Gets the latest sources of the repository "GIT_REPO" and prepares the .dsc file.
	  build: Uses pbuilder to build the Tox client from the .dsc file generated.
	  help: Displays this help.
	
	Options of "prepare":
	  --conf: Path to the configuration file.
	  --dist: Sets the target distribution.
	  --arch: Sets the target architecture.
	
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
