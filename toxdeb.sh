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
	local client_version i
	local client dist arch branch
	local conf_file
	
	# Check the number of arguments before going forward
	[[ ${ARGS_NB} -lt 1 ]] \
		&& { error 'argument_missing' ; return $? ; }
	
	# Warn if this is run as root
	[[ $(id -u) -eq 0 ]] \
		&& echo "WARNING: That's weird, this script shouldn't be running with root privileges (<.<)"
		
	# Get the command given
	case ${ARGS[0]} in
		
		# Build the client
		build)
			
			# Get the configuration...
			case ${ARGS[1]} in
				
				# ... based on the name of the Jenkins job
				auto)
					
					# Get the information from the Jenkins job name
					client=$(get_job_info 'client_name')
					dist=$(get_job_info 'distribution')
					arch=$(get_job_info 'architecture')
					branch=$(get_job_info 'branch')
					
					# Use the specific config file if possible
					if [[ -e "./configs/${client}-${dist}.cfg" ]]
					then
						conf_file="./configs/${client}-${dist}.cfg"
						
					# Else use the default one
					elif [[ -e "./configs/${client}-default.cfg" ]]
					then
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
					[[ ${ARGS_NB} -ne 10 ]] \
						&& { error 'manual_options' ; return $? ; }
			
					# Get the arguments
					for i in 2 4 6 8
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
							--branch)
								branch=${ARGS[$(($i + 1))]}
								;;
							*)
								error 'unknown_option' "${ARGS[$i]}"
								return $?
								;;
						esac
					done
					;;
				
				# Wrong argument
				*)
					error 'unknown_argument' "${ARGS[1]}" 'build'
					return $?
					;;
			esac
			
			# If the configuration file exists, sources it
			if [[ -e "$conf_file" ]]
			then
				echo "INFO: Using configuration file ${conf_file##*/}"
				source ${conf_file}
			else
				error 'conf_file' "${conf_file##*/}"
				return $?
			fi
			
			# Test the presence of the source folder
			[[ -d "${CLIENT_NAME,,}_src" ]] \
				|| { error 'source_folder' "${CLIENT_NAME,,}_src" ; return $? ; }
			
			# Get the client version
			client_version=$(get_version)
			
			# Fill the debian/ folder template
			fill_templates "${client_version}" "$dist" "$arch" "$branch" || return $?
			
			# Prepare the source to be built
			prepare_source "${client_version}" || return $?
			
			# Launch the build process
			build_client "$dist" "$arch" || return $?
			;;
			
		# Display the help
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

# Get the version of the client
get_version() {

	# Local variables
	local version_files

	# Get the "main" headers in the folder
	version_files=($(find "${CLIENT_NAME,,}_src" -name "${VERSION_FILE}"))
	
	# Return the version
	echo $(grep -i version ${version_files[@]} | grep -oE '([0-9]{1,}\.){2}[0-9]{1,}')
	
	return 0
}

# Get information from the job name
get_job_info() {

	# Local variables
	local attribute=$1
	local tmp value
	
	case $attribute in
		
		# Get the distribution
		distribution)
			value=$(echo ${JOB_NAME} | grep -o 'jessie\|stretch\|sid\|xenial\|yakkety\|zesty')
			;;
		
		# Get the client name
		client_name)
			value=$(echo ${JOB_NAME} | cut -d '_' -f 1)
			;;
		
		# Get the architecture
		architecture)
			tmp=$(echo ${JOB_NAME} | grep -o '_x86_\|_x86-64_')
			case $tmp in
				'_x86_')
					value='i386'
					;;
				'_x86-64_')
					value='amd64'
					;;
			esac
			;;
		
		# Get the branch (stable or nightly)
		branch)
			value=$(echo ${JOB_NAME} | grep -o 'stable\|nightly')
			;;
		
	esac
	
	# Return the value requested (lowercase)
	[[ -n "$value" ]] \
		&& echo "${value,,}" \
		|| { error 'auto_config' "$attribute" ; return $? ; }
			
	return 0
}

# Fills the templates of the debian/ folder
fill_templates() {

	# Local variables
	local client_version=$1
	local distribution=$2
	local architecture=$3
	local branch=$4
	local packages_url debian_revision
	local date_rfc year
	local override
	
	# Date-related stuff
	date_rfc=$(date -R)
	year=$(date '+%Y')
	
	# Get the revision number from pkg.tox.chat
	packages_url="https://pkg.tox.chat/debian/dists/${branch}/${distribution}/binary-${architecture}/Packages"
	debian_revision=$(wget -qO - "${packages_url}" \
		| grep -E "^Filename:.*${CLIENT_NAME,,}_${client_version}-[0-9]{1,}_${architecture}.deb$" \
		| gawk -F '[-_]' '{print $3}')
	
	# Set the revision
	[[ -z debian_revision ]] \
		&& debian_revision=1 \
		|| debian_revision=$((${debian_revision} + 1))
	
	# Go in the debian/ folder
	cd debian
	
	# Proceed to the changes which do not need logic
	sed -e "s/#BUILD_DEPENDS#/${BUILD_DEPENDS}/g" \
		-e "s/#CLIENT_NAME#/${CLIENT_NAME}/g" \
		-e "s/#CLIENT_VERSION#/${client_version}/g" \
		-e "s,#COPYRIGHT_ORGANISATION#,${COPYRIGHT_ORGANISATION},g" \
		-e "s,#COPYRIGHT_WEBSITE#,${COPYRIGHT_WEBSITE},g" \
		-e "s/#COPYRIGHT_YEARS#/${COPYRIGHT_YEARS}/g" \
		-e "s/#DATE_RFC#/${date_rfc}/g" \
		-e "s/#DEBIAN_REVISION#/${debian_revision}/g" \
		-e "s/#DEPENDS#/${DEPENDS}/g" \
		-e "s/#DESC_LONG#/${DESC_LONG}/g" \
		-e "s/#DESC_SHORT#/${DESC_SHORT}/g" \
		-e "s,#DH_EXTRA_ARGS#,${DH_EXTRA_ARGS},g" \
		-e "s/#DISTRIBUTION#/${distribution}/g" \
		-e "s,#GIT_REPO#,${GIT_REPO},g" \
		-e "s,#HTTP_REPO#,${HTTP_REPO},g" \
		-e "s/#LC_CLIENT_NAME#/${CLIENT_NAME,,}/g" \
		-e "s/#MAINT_EMAIL#/${MAINT_EMAIL}/g" \
		-e "s/#MAINT_NAME#/${MAINT_NAME}/g" \
		-e "s/#YEAR#/${year}/g" \
		-i $(find . -type f)

	# Extra dh overrides
	if [[ -n "${DH_EXTRA_OVERRIDES[@]}" ]]
	then
		for override in "${DH_EXTRA_OVERRIDES[@]}"
		do
			echo "$(echo $override | cut -d ' ' -f 1)" >> rules
			echo -e "\t$(echo $override | cut -d ' ' -f 2-)" >> rules
		done
	fi
	
	# Back to the parent directory
	cd ..
	
	return 0
}

# Prepare the source for pbuilder, generating a .dsc file
prepare_source() {

	# Local variables
	local client_version=$1
	local parent_folder
	local changelog_file
	local manpage
	local line gawk_var
	
	# Rename the parent folder
	parent_folder="${CLIENT_NAME,,}-${client_version}"
	mv "${CLIENT_NAME,,}_src" "${parent_folder}"
	
	# Convert the source as a .orig.tar.gz archive
	tar -zcf "${CLIENT_NAME,,}_${client_version}.orig.tar.gz" "${parent_folder}"
	
	# Move the "almost" complete debian/ folder
	mv debian ${parent_folder}
	
	# Goes in the folder
	cd ${parent_folder}
	
	# Add the manpage
	manpage=$(find . -name ${CLIENT_NAME,,}.1)
	[[ -n "$manpage" ]] \
		&& cp $manpage debian/ \
		|| echo 'WARNING: No manpage found!'
	
	# Add changelog from CHANGELOG.md
	changelog_file=$(find . -name 'CHANGELOG.md')
	
	if [[ -n "$changelog_file" ]]
	then
		
		# Find the section from which to extract the changelog, default: "Unreleased"
		grep -q "^## \[v${client_version}\]" $changelog_file \
			&& gawk_var="v${client_version}" \
			|| { grep -q '^## \[Unreleased\]' $changelog_file && gawk_var='Unreleased' ; }
		
		# If a matching line has been found
		if [[ -n "${gawk_var}" ]]
		then
			
			# Inform about the changelog entry taken
			echo "INFO: Generating the changelog using section \"${gawk_var}\" of CHANGELOG.md."
			
			# Insert the changelog at the right place
			while IFS= read line
			do
			
				# It's the right place to insert the changelog
				if [[ "$line" == '#CHANGELOG#' ]]
				then

					gawk -v version=${gawk_var} '$0 ~ "^## \\[" version "\\].+",/^##/ && $0 !~ version {
						if(match($0, /^[*]{2}/)) {
							gsub(/[*]/, "")
							print "  *", $0
						} else if (match($0, /^-/)){
							gsub(/^- /, "")
							$0 = gensub(/\\([_()#])/, "\\1", "g")
							sub(/ \[#[0-9]*\].*/, "")
							print "    -", $0
						}
					}' ${changelog_file} \
					>> debian/changelog_tmp
				
				# Else, echo the line
				else
					echo "$line" >> debian/changelog_tmp
				fi
			
			done < <(cat debian/changelog)
			
			# Moves the temporary changelog
			mv debian/changelog_tmp debian/changelog
		
		fi
	fi
	
	# If there is no changelog or no matching section was used
	if [[ -z "${changelog_file}" || -z "${gawk_var}" ]]
	then
		echo 'WARNING: No CHANGELOG.md found! No changelog will be produced.'
		sed -i 's/#CHANGELOG#/  * No changelog available./' debian/changelog
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
	[[ $? -ne 0 ]] \
		&& { error 'pbuilder_failed' ; return $? ; }
	
	return 0
}

# Error handling
error() {

	local err=$1

	# Display the error
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
			echo "Couldn't automatically find the attribute \"$2\" for this job." >&2
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
			echo "Unknown option $2 for operation \"manual\"." >&2
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
	  --branch: The type of build (stable or nightly)
	
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
