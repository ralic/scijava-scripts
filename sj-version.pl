#!/bin/sh

# Script to print version properties for a given parent POM release.

use strict;

# Examples:
# sj-version.pl 1.70
# sj-version.pl 1.70 1.74
# sj-version.pl imagej:2.7 imagej:2.1
# sj-version.pl org.scijava:pom-scijava:2.1

my $version = $1;
my $diff = $2;

my $repo = "http://maven.imagej.net/content/groups/public";

sub props($) {
	my ($arg) = @_;

	if (-f "$arg") {
		# extract version properties from the given file path
		open POM, $arg;
		my $versions = <POM>;
		close(POM);
	}
	else {
		url="$repo/org/scijava/pom-scijava/$1/pom-scijava-$1.pom"
		versions=$(curl -s "$url")
		# assume argument is a version number of pom-scijava
	}
	echo "$versions" | \
		grep '\.version>' | \
		sed -E -e 's/^				(.*)/\1 [DEV]/' | \
		sed -E -e 's/^	*<(.*)\.version>(.*)<\/.*\.version>/\1 = \2/' | \
		sort
}

if [ -z "$version" ]
then
	# try to extract version from pom.xml in this directory
	if [ -e pom.xml ]
	then
		groupId=$(grep -A 3 '<parent>' pom.xml | \
			grep '<groupId>' | \
			sed 's/<\/.*//' | \
			sed 's/.*>//')
		artifactId=$(grep -A 3 '<parent>' pom.xml | \
			grep '<artifactId>' | \
			sed 's/<\/.*//' | \
			sed 's/.*>//')
		version=$(grep -A 3 '<parent>' pom.xml | \
			grep '<version>' | \
			sed 's/<\/.*//' | \
			sed 's/.*>//')
		version="$groupId:$artifactId:$version"
	fi
fi

if [ -z "$version" ]
then
	echo "Usage: sj-version.sh version [version-to-diff]"
	exit 1
fi

if [ -n "$diff" ]
then
	# compare two versions
	props $version > $version.tmp
	props $diff > $diff.tmp
	diff -y $version.tmp $diff.tmp
	rm $version.tmp $diff.tmp
else
	# dump props for one version
	props $version
fi
