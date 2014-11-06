#!/bin/sh

# This script uses the ImageJ Maven repository at http://maven.imagej.net/
# to fetch an artifact, or to determine the state of it.

# error out whenever a command fails
set -e
local=false

root_url () {
	test snapshots != "$2" || {
		if curl -fs http://maven.imagej.net/service/local/repositories/sonatype-snapshots/content/"$1"/maven-metadata.xml > /dev/null 2>&1
		then
			echo http://maven.imagej.net/service/local/repositories/sonatype-snapshots/content
		else
			echo http://maven.imagej.net/content/repositories/snapshots
		fi
		return
	}
	echo http://maven.imagej.net/service/local/repo_groups/public/content
}

die () {
	echo "$*" >&2
	exit 1
}

# Helper (thanks, BSD!)

get_mtime () {
	stat -c %Y "$1"
}
case "$(uname -s 2> /dev/null)" in
MINGW*)
	get_mtime () {
		date -r "$1" +%s
	}
	;;
Darwin)
	get_mtime () {
		stat -f %m "$1"
	}
	;;
esac

# Parse <groupId>:<artifactId>:<version> triplets (i.e. GAV parameters)

groupId () {
	echo "${1%%:*}"
}

artifactId () {
	result="${1#*:}"
	echo "${result%%:*}"
}

version () {
	result="${1#*:}"
	case "$result" in
	*:*)
		echo "${1##*:}"
		;;
	esac
}

# Given an xml, extract the first <tag>

extract_tag () {
	result="${2%%</$1>*}"
	case "$result" in
	"$2")
		;;
	*)
		echo "${result#*<$1>}"
		;;
	esac
}

# Given an xml, extract the last <tag>

extract_last_tag () {
	result="${2##*<$1>}"
	case "$result" in
	"$2")
		;;
	*)
		echo "${result%%</$1>*}"
		;;
	esac
}

# Given an xml, skip all <tag> sections

skip_tag () {
	result="$2"
	while true
	do
		case "$result" in
		*"<$1>"*)
			result="${result%%<$1>*}${result#*</$1>}"
			;;
		*)
			break
			;;
		esac
	done
	echo "$result"
}

# Given the xml of a POM, find the parent GAV

parent_gav_from_pom_xml () {
	pom="$1"
	parent="$(extract_tag parent "$pom")"
	if test -n "$parent"
	then
		groupId="$(extract_tag groupId "$parent")"
		artifactId="$(extract_tag artifactId "$parent")"
		version="$(extract_tag version "$parent")"
		echo "$groupId:$artifactId:$version"
	fi
}

# Given a GAV parameter, determine the base URL of the project

project_url () {
	gav="$1"
	artifactId="$(artifactId "$gav")"
	infix="$(groupId "$gav" | tr . /)/$artifactId"
	version="$(version "$gav")"
	case "$version" in
	*SNAPSHOT)
		echo "$(root_url $infix snapshots)/$infix"
		;;
	*)
		# Release could be in either releases or thirdparty; try releases first
		project_url="$(root_url $infix releases)/$infix"
		header=$(curl -Is "$project_url/")
		case "$header" in
		HTTP/1.?" 200 OK"*)
			;;
		*)
			project_url="$(root_url $infix thirdparty)/$infix"
			;;
		esac
		echo "$project_url"
		;;
	esac
}

# Given a GAV parameter, determine the URL of the .jar file

jar_url () {
	gav="$1"
	artifactId="$(artifactId "$gav")"
	version="$(version "$gav")"
	infix="$(groupId "$gav" | tr . /)/$artifactId/$version"

	cached=$HOME/.m2/repository/$infix/

	if $local && test -d "$cached"
	then
		echo "$cached$artifactId-$version.jar"
	else
		case "$version" in
		*-SNAPSHOT)
			url="$(root_url $infix snapshots)/$infix/maven-metadata.xml"
			metadata="$(curl -s "$url")"
			timestamp="$(extract_tag timestamp "$metadata")"
			buildNumber="$(extract_tag buildNumber "$metadata")"
			version=${version%-SNAPSHOT}-$timestamp-$buildNumber
			echo "$(root_url $infix snapshots)/$infix/$artifactId-$version.jar"
			;;
		*)
			echo "$(root_url $infix releases)/$infix/$artifactId-$version.jar"
			;;
		esac
	fi
}

# Given a GAV parameter, return the URL to the corresponding .pom file

pom_url () {
	url="$(jar_url "$1")"
	echo "${url%.jar}.pom"
}

# Given a POM file, find its GAV parameter

gav_from_pom () {
	pom="$(cat "$1")"
	parent="$(extract_tag parent "$pom")"
	pom="$(skip_tag parent "$pom")"
	pom="$(skip_tag dependencies "$pom")"
	pom="$(skip_tag profiles "$pom")"
	pom="$(skip_tag build "$pom")"
	groupId="$(extract_tag groupId "$pom")"
	test -n "$groupId" || groupId="$(extract_tag groupId "$parent")"
	artifactId="$(extract_tag artifactId "$pom")"
	version="$(extract_tag version "$pom")"
	test -n "$version" || version="$(extract_tag version "$parent")"
	echo "$groupId:$artifactId:$version"
}

# Given a GAV parameter, find its parent's GAV

parent_gav () {
	gav="$1"
	groupId="$(groupId "$gav")"
	artifactId="$(artifactId "$gav")"
	version="$(version "$gav")"
	test -n "$version" || version="$(latest_version "$gav")"
	pom="$(read_pom "$groupId:$artifactId:$version")"
	parent_gav_from_pom_xml "$pom"
}

# Given a POM file, find its parent's GAV

parent_gav_from_pom () {
	pom="$(cat "$1")"
	parent_gav_from_pom_xml "$pom"
}

# Given a POM file, extract its packaging

packaging_from_pom () {
	pom="$(cat "$1")"
	pom="$(skip_tag parent "$pom")"
	pom="$(skip_tag dependencies "$pom")"
	pom="$(skip_tag profiles "$pom")"
	pom="$(skip_tag build "$pom")"
	packaging="$(extract_tag packaging "$pom")"
	echo "${packaging:-jar}"
}

# Given a GAV parameter possibly lacking a version, determine the latest version

latest_version () {
	metadata="$(curl -s "$(project_url "$1")"/maven-metadata.xml)"
	latest="$(extract_tag release "$metadata")"
	test -n "$latest" || latest="$(extract_tag latest "$metadata")"
	test -n "$latest" || latest="$(extract_last_tag version "$metadata")"
	echo "$latest"
}

# Given a GA parameter, invalidate the cache in ImageJ's Nexus' group/public

SONATYPE_DATA_CACHE_URL=http://maven.imagej.net/service/local/data_cache/repositories/sonatype/content
SONATYPE_SNAPSHOTS_DATA_CACHE_URL=http://maven.imagej.net/service/local/data_cache/repositories/sonatype-snapshots/content
invalidate_cache () {
	ga="$1"
	artifactId="$(artifactId "$ga")"
	infix="$(groupId "$ga" | tr . /)/$artifactId"
	curl --netrc -i -X DELETE \
		$SONATYPE_DATA_CACHE_URL/$infix/maven-metadata.xml &&
	curl --netrc -i -X DELETE \
		$SONATYPE_SNAPSHOTS_DATA_CACHE_URL/$infix/maven-metadata.xml &&
	version="$(latest_version "$ga")" &&
	infix="$infix/$version" &&
	curl --netrc -i -X DELETE \
		$SONATYPE_DATA_CACHE_URL/$infix/$artifactId-$version.pom &&
	if test "$artifactId" = "${artifactId#pom-}"
	then
		curl --netrc -i -X DELETE \
			$SONATYPE_DATA_CACHE_URL/$infix/$artifactId-$version.jar
	fi
}

# Generate a temporary file; not thread-safe

tmpfile () {
	i=1
	while test -f /tmp/precompiled.$i"$1"
	do
		i=$(($i+1))
	done
	echo /tmp/precompiled.$i"$1"
}

# Given a GAV or a path, read the POM

read_pom () {
	case "$1" in
	pom.xml|*/pom.xml|*\\pom.xml)
		cat "$1"
		;;
	*)
		url=$(pom_url "$1")
		case "$url" in
		http*)
			curl -s "$url"
			;;
		*)
			cat "$url"
			;;
		esac
		;;
	esac
}

# Given a GAV parameter (or pom.xml path) and a name, resolve a property (falling back to parents)

get_property () {
	gav="$1"
	key="$2"
	case "$key" in
	imagej1.version)
		latest_version net.imagej:ij
		return
		;;
	project.groupId)
		groupId "$gav"
		return
		;;
	project.version)
		version "$gav"
		return
		;;
	esac
	while test -n "$gav"
	do
		pom="$(read_pom "$gav")"
		properties="$(extract_tag properties "$pom")"
		property="$(extract_tag "$key" "$properties")"
		if test -n "$property"
		then
			echo "$property"
			return
		fi
		gav="$(parent_gav_from_pom_xml "$pom")"
	done
	die "Could not resolve \${$2} in $1"
}

# Given a GAV parameter and a string, expand properties

expand () {
	gav="$1"
	string="$2"
	result=
	while true
	do
		case "$string" in
		*'${'*'}'*)
			result="$result${string%%\$\{*}"
			string="${string#*\$\{}"
			key="${string%\}*}"
			result="$result$(get_property "$gav" "$key")"
			string="${string#$key\}}"
			;;
		*)
			echo "$result$string"
			break
			;;
		esac
	done
}

# Given a GAV parameter, make a list of its dependencies (as GAV parameters)

get_dependencies () {
	get_dependencies_helper "$(read_pom "$1")"
}

# Gets dependencies from the pom created by "mvn help:effective-pom"
# in the current working directory

get_effective_dependencies () {
	get_dependencies_helper "$(mvn help:effective-pom)"
}

# Helper method to perform actual dependency parsing

# TODO iterate through parents to expand ${}, either in properties or
# dependency management
# TODO restrict to just core dependency

get_dependencies_helper () {
	pom=$1
	while true
	do
		case "$pom" in
		*'<dependency>'*)
			dependency="$(extract_tag dependency "$pom")"
			scope="$(extract_tag scope "$dependency")"
			case "$scope" in
			''|compile)
				groupId="$(expand "$1" "$(extract_tag groupId "$dependency")")"
				artifactId="$(extract_tag artifactId "$dependency")"
				version="$(expand "$1" "$(extract_tag version "$dependency")")"
				echo "$groupId:$artifactId:$version"
				;;
			esac
			pom="${pom#*</dependency>}"
			;;
		*)
			break;
		esac
	done
}

# Given a GAV parameter and a space-delimited list of GAV parameters, expand
# the list by the first parameter and its dependencies (unless the list already
# contains said parameter)

get_all_dependencies () {
	case " $2 " in
	*" $1 "*)
		;; # list already contains the depdendency
	*)
		gav="$1"
		set "" "$2 $1"
		for dependency in $(get_dependencies "$gav")
		do
			set "" "$(get_all_dependencies "$dependency" "$2")"
		done
		;;
	esac
	echo "$2"
}

# Given a GAV parameter, download the .jar file

get_jar () {
	url="$(jar_url "$1")"
	tmpfile="$(tmpfile .jar)"
	curl -s "$url" > "$tmpfile"
	test "<html" != "$(head -c 5 "$tmpfile")" ||
	curl -s "${url%.jar}.nar" > "$tmpfile"
	test PK = "$(head -c 2 "$tmpfile")"
	echo "$tmpfile"
}

# Given a GAV parameter, get the commit from the manifest of the deployed .jar

commit_from_gav () {
	jar="$(get_jar "$1")"
	unzip -p "$jar" META-INF/MANIFEST.MF |
	sed -n -e 's/^Implementation-Build: *//pi' |
	tr -d '\r'
	rm "$jar"
}

# Given a GAV parameter, determine whether the .jar file is already in plugins/
# or jars/

is_jar_installed () {
	artifactId="$(artifactId "$1")"
	version="$(version "$1")"
	file=$artifactId-$version.jar
	test -f "$file" || file=../plugins/$file
	test -f "$file" || return 1
	case "$version" in
	*-SNAPSHOT)
		# is the file younger than a day?
		mtime="$(get_mtime "$file")"
		test "$(($mtime-$(date +%s)))" -gt -86400
		;;
	esac
}

# Given a .jar file, determine whether it is an ImageJ 1.x plugin

is_ij1_plugin () {
	unzip -l "$1" plugins.config > /dev/null 2>&1
}

# Given a GAV parameter, download the .jar file and its dependencies as needed
# and install them into plugins/ or jars/, respectively

install_jar () {
	for gav in $(get_all_dependencies "$1")
	do
		if ! is_jar_installed "$gav"
		then
			tmp="$(get_jar "$gav")"
			name="$(artifactId "$gav")-$(version "$gav").jar"
			if test -d ../plugins && is_ij1_plugin "$tmp"
			then
				mv "$tmp" "../plugins/$name"
			else
				mv "$tmp" "$name"
			fi
		fi
	done
}

# Determine whether a local project (specified as pom.xml) needs to be deployed

is_deployed () {
	gav="$(gav_from_pom "$1")" &&
	commit="$(commit_from_gav "$gav")" &&
	test -n "$commit" &&
	dir="$(dirname "$1")" &&
	(cd "$dir" &&
	 git diff --quiet "$commit".. -- .)
}

# Fails with exit code 1 if the given gav contains SNAPSHOT

test_snapshot () {
	if [[ "$1" == *"SNAPSHOT"* ]]
	then
		echo "Found SNAPSHOT: $1"
		exit 1
	fi
}

# Test all parents of the given pom.xml for SNAPSHOT versions

validate_parent () {
	parent="$(parent_gav "$1")"
	return
#	while [[ "$parent" != "$NO_PARENT" ]]
#		do
#			test_snapshot "$parent"
#			parent="$(parent_gav "$parent")"
#		done
}

# Recursively test all parents and dependencies of the
# given gav for SNAPSHOT versions

validate_gav () {
	# Test the gav itself
	test_snapshot "$1"

	# Test the gav's parents
	validate_parent "$1"

	# Test the gav's dependencies
	deps="$(get_dependencies $1)"
	for dep in $deps
	do
		echo "sub validating: $dep"
		validate_gav "$dep"
	done
}

# Determine whether the pom.xml in the cwd has any trace of SNAPSHOTS

validate_no_snapshots () {
	basegav="$(gav_from_pom pom.xml)"

	# Fail if the current pom is a snapshot
	test_snapshot "$basegav"

	# Test the base pom's parent
	validate_parent "$basegav"

	# Test the effective dependencies and their parents
	deps="$(get_effective_dependencies)"
	for dep in $deps
	do
		echo "top-level validating: $dep"
		validate_gav "$dep"
	done
}

# Determine which function to call

process_args() {
	case "$1" in
	commit)
		commit_from_gav "$2"
		;;
	deps|dependencies)
		get_dependencies "$2"
		;;
	all-deps|all-dependencies)
		get_all_dependencies "$2" |
		tr ' ' '\n' |
		grep -v '^$'
		;;
	latest-version)
		latest_version "$2"
		;;
	invalidate-cache)
		invalidate_cache "$2"
		;;
	gav-from-pom)
		gav_from_pom "$2"
		;;
	parent-gav)
		parent_gav "$2"
		;;
	pom-url)
		pom_url "$2"
		;;
	parent-gav-from-pom)
		parent_gav_from_pom "$2"
		;;
	packaging-from-pom)
		packaging_from_pom "$2"
		;;
	property-from-pom|get-property|property)
		if test $# -lt 3
		then
			get_property pom.xml "$2"
		else
			get_property "$2" "$3"
		fi
		;;
	install)
		install_jar "$2"
		;;
	is-deployed)
		is_deployed "$2"
		;;
	validate-no-snapshots)
		validate_no_snapshots
		;;
	*)
		test $# -eq 0 || echo "Unknown command: $1" >&2
		die "Usage: $0 [option...] [command] [argument...]"'
		Options:

		local
			Causes commands to check the local maven cache before a remote
			repository.

		Commands:

		commit <groupId>:<artifactId>:<version>
			Gets the commit from which the given artifact was built.

		dependencies <groupId>:<artifactId>:<version>
			Lists the direct dependencies of the given artifact.

		all-dependencies <groupId>:<artifactId>:<version>
			Lists all dependencies of the given artifact, including itself and
			transitive dependencies.

		latest-version <groupId>:<artifactId>[:<version>]
			Prints the current version of the given artifact (if "SNAPSHOT" is
			passed as version, it prints the current snapshot version rather
			than the release one).

		invalidate-cache <groupId>:<artifactId>
			Invalidates the version cached in the ImageJ Nexus from OSS Sonatype,
			e.g. after releasing a new version to Sonatype. Requires appropriate
			credentials in $HOME/.netrc for http://maven.imagej.net/.

		parent-gav <groupId>:<artifactId>[:<version>]
			Prints the GAV parameter of the parent project of the given artifact,
			or "no parent found" if the given gav has no parent.

		pom-url <groupId>:<artifactId>:<version>
			Gets the URL of the POM describing the given artifact.

		gav-from-pom <pom.xml>
			Prints the GAV parameter described in the given pom.xml file.

		parent-gav-from-pom <pom.xml>
			Prints the GAV parameter of the parent project of the pom.xml file, or
			"no parent found" if the given pom has no parent.

		packaging-from-pom <pom.xml>
			Prints the packaging type of the given project.

		property-from-pom <pom.xml> <property-name>
			Prints the property specified in the pom.xml file (or in its parents).

		install <groupId>:<artifactId>:<version>
			Installs the given artifact and all its dependencies; if the artifact
			or dependency to install is an ImageJ 1.x plugin and the parent
			directory contains a subdirectory called "plugins", it will be
			installed there, otherwise into the current directory.

		is-deployed <pom.xml>
			Tests whether the specified project is deployed alright. Fails
			with exit code 1 if not.

		validate-no-snapshots
			Tests whether the pom in the current working directory specifies any
			SNAPSHOT dependencies, contains a SNAPSHOT parent pom in its hierarchy,
			or has a dependency with a SNAPSHOT parent pom in its hierarchy. This
			is a recursive test and is more thorough than the maven enforcer
			no-snapshot rule. Fails with exit code 1 if a SNAPSHOT is found.
		'
		;;
	esac
}

# Preprocess arguments, removing global flags

ARGS=()
for var in "$@"
do
	case "$var" in
	local)
		local=true
		;;
	*)
		ARGS+=("$var")
		;;
	esac
done

process_args "${ARGS[@]}"
