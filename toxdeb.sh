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
	local client_version config i
	local config client dist arch
	local conf_file
	
	# Check the number of arguments before going forward
	[[ ${ARGS_NB} -lt 1 ]] && { error 'argument_missing' ; return $? ; }
	
	# Warn if this is run as root
	[[ $(id -u) -eq 0 ]] && echo "WARNING: That's weird, this script shouldn't be running with root privileges (<.<)"
		
	# Get the command given
	case ${ARGS[0]} in
		
		# Build the client
		build)
			
			# Get the configuration...
			case ${ARGS[1]} in
			
				# ... based on the name of the Jenkins job
				auto)
					
					# Get the information from the Jenkins job name
					config=$(get_config_auto)
					client=$(echo $config | cut -d ',' -f 1)
					dist=$(echo $config | cut -d ',' -f 2)
					arch=$(echo $config | cut -d ',' -f 3)
					
					# Use the specific config file if possible
					if [[ -e "./configs/${client}-${dist}.cfg" ]]
					then
						echo "INFO: Using configuration file ${client}-${dist}.cfg"
						conf_file="./configs/${client}-${dist}.cfg"
						
					# If it doesn't exist, use the default one
					elif [[ -e "./configs/${client}-default.cfg" ]]
					then
						echo "INFO: Using configuration file ${client}-default.cfg"
						conf_file="./configs/${client}-default.cfg"
					
					# Else, you can't go much further :P
					else
						error 'conf_file' "${client}-${dist}.cfg or ${client}-default.cfg"
						return $?
					fi
					;;
				
				# ... manually given as options
				manual)
					
					# Check the number of arguments before going forward
					[[ ${ARGS_NB} -ne 8 ]] && { error 'manual_options' ; return $? ; }
			
					# Get the arguments
					for i in 2 4 6
					do
						case ${ARGS[$i]} in
							--conf)
								conf_file=${ARGS[$(($i + 1))]}
								;;
							--dist)
								dist=${ARGS[$(($i + 1))]}
								;;
							--arch)
								arch=${ARGS[$(($i + 1))]}
								;;
							*)
								error 'unknown_option' "${ARGS[$i]}"
								return $?
								;;
						esac
					done
					
					# Test if the configuration file exists
					[[ -e "$conf_file" ]] || { error 'conf_file' "${conf_file}" ; return $? ; }
					;;
				
				# Wrong argument
				*)
					error 'unknown_argument' "${ARGS[1]}" 'build'
					return $?
					;;
			esac
			
			# Source the configuration file
			source ${conf_file}
			
			# Tests the presence of the source folder
			[[ -d "${CLIENT_NAME,,}_src" ]] \
				|| { error 'source_folder' "${CLIENT_NAME,,}_src" ; return $? ;}
			
			# Get the client version
			client_version=$(get_version)
			
			# Prepares the folders
			prepare_folders "$client_version" || return $?
			
			# Prepares the source to be built
			prepare_source "$client_version" "$dist" || return $?
			
			# Launch the build process
			build_client "$dist" "$arch" || return $?
			;;
			
		# Displays the help
		help)
			help
			return $?
			;;
		
		# Well... at least you tried :P
		*)
			error 'unknown_argument' "${ARGS[0]}" "$PROGNAME"
			return $?
			;;
	esac
	
	# If everything went well, SUCCESS!
	return 0
}

# Get the build information (for auto mode)
get_config_auto() {

	# Local variables
	local client dist arch
	local config
	
	# Gets the client name
	client=$(echo ${JOB_NAME} | cut -d '_' -f 1)
	
	# Gets the distribution
	config=$(echo ${JOB_NAME} | grep -o 'wheezy\|jessie\|stretch\|sid\|trusty\|utopic\|vivid\|wily\|xenial')
	[[ -n "$config" ]] \
		&& dist="$config" \
		|| { error 'auto_config' 'distribution' ; return $? ; }
	
	# Gets the architecture
	config=$(echo ${JOB_NAME} | grep -o '_x86_\|_x86-64_')
	case $config in
		'_x86_')
			arch='i386'
			;;
		'_x86-64_')
			arch='amd64'
			;;
		*)
			error 'auto_config' 'architecture'
			return $?
			;;
	esac
	
	# Returns the parameters found
	echo "${client,,},${dist},${arch}"
	
	return 0
}

# Gets the version of the client
get_version() {

	# Local variables
	local version_files

	# Get the "main" headers in the folder
	version_files=($(find "${CLIENT_NAME,,}_src" -name "${VERSION_FILE}"))
	
	# Return the version
	echo $(grep VERSION ${version_files[@]} | grep -oE '([0-9]{1,}\.)+[0-9]{1,}')
	
	return 0
}

# Set up correctly the folders for dh_make
prepare_folders() {

	# Local variables
	local client_version=$1
	local parent_folder
	
	# Correctly rename the source folder (becoming the parent folder)
	parent_folder="${CLIENT_NAME,,}-${client_version}"
	mv "${CLIENT_NAME,,}_src" "${parent_folder}"
	
	# Convert the source as a .tar.gz archive
	tar -zcf "${parent_folder}.tar.gz" "${parent_folder}"
	
	return 0
}

# Prepare the source for pbuilder, generating a .dsc file
prepare_source() {

	# Local variables
	local client_version=$1
	local distribution=$2
	local parent_folder
	local changelog_file changelog_footer
	local manpage
	
	# Sets the parent_folder
	parent_folder="${CLIENT_NAME,,}-${client_version}"
	
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
	manpage=$(find . -name ${CLIENT_NAME,,}.1)
	[[ -n "$manpage" ]] \
		&& cp $manpage debian/ \
		|| echo 'WARNING: No manpage found!'
	
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
	
	# Adds changelog from CHANGELOG.md
	changelog_file=$(find . -name 'CHANGELOG.md')
	
	if [[ -n "$changelog_file" ]]
	then
	
		# Saves the footer
		changelog_footer=$(grep ' --' debian/changelog)
		
		# Delete all lines but keep the header
		sed -i '1,2!d' debian/changelog
		
		# Inserts the changelog
		gawk '{if(match($0, /## v?([0-9]\.){2}[0-9].*/) != 0){i++} ; if(match($0, /#### .*/) != 0){j++} ; if(i != 2 && j >= 1){print} else if(i == 2){exit}}' ${changelog_file} | \
		sed -e '/^</d' \
			-e '/^$/d' \
			-e 's/  \+\([^*]\)/ \1/g' \
			-e 's/[*]\{2,\}//g' \
			-e 's/#### \(.*\)/\n  * \1:/' \
			-e 's/ (\[[0-9a-f]\{8\}\].*//' \
			-e 's/^\( *\)[*]/    \1*/' \
		>> debian/changelog
		
		# Add the footer
		echo -e "\n${changelog_footer}" >> debian/changelog
		
	else
		echo 'WARNING: No CHANGELOG.md found! No changelog will be produced.'
		sed -i 's/^  [*].*/  * No changelog available./g' debian/changelog
	fi
	
	# Call dpkg-source to generate the .dsc file
	dpkg-source -b .
	
	# Back to the parent directory
	cd ..
	
	return 0
}

# Build the Tox client with pbuilder
build_client() {

	# Local variables
	local distribution=$1
	local architecture=$2
	
	# Set the environment variables
	export DIST=${distribution}
	export ARCH=${architecture}
	export REPOBASE=$PWD
	
	# Call pbuilder
	sudo pbuilder --update --override-config
	sudo pbuilder build --buildresult $PWD *.dsc
	[[ $? -ne 0 ]] && { error 'pbuilder_failed' ; return $?; }
	
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
			echo "The configuration file ($2) doesn't exist." >&2
			;;
		source_folder)
			echo "The source folder $2 was expected in the workspace but it is missing!" >&2
			;;
		auto_config)
			echo "Couldn't find automatically the $2 for this job." >&2
			echo "Please rename your job or use the manual option." >&2
			;;
		manual_options)
			echo 'The operation "build manual" expects 3 options with their respective values.' >&2
			echo "Use \"${PROGNAME} help\" to get further help." >&2
			;;
		unknown_argument)
			echo "Unknown argument $2 for $3." >&2
			;;
		unknown_option)
			echo "Unknown option $2 for operation \"prepare\"." >&2
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
	Usage: ${PROGNAME} [ build [ manual <options> | auto ] | help ]
	
	Operations:
	  build manual: Builds the Tox client based on the options given.
	  build auto: Builds the Tox client based on the Jenkins job name.
	  help: Displays this help.
	
	Options of "build manual" (mandatory):
	  --conf: Path to the configuration file.
	  --dist: Sets the target distribution.
	  --arch: Sets the target architecture.
	
	One will probably run: ./${PROGNAME} build auto for a job such as "uTox_pkg_linux_deb_shared_jessie_x86-64_nightly_release"
	In case of manual configuration: ./${PROGNAME} build --dist jessie --arch amd64 --conf ./configs/utox-jessie.cfg
	Please make sure that the configuration file is correct before running this tool.
	EOF

	return 0
}

# Launch the main function
main

# Exit with the correct exit code
exit $?
