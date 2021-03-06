#!/bin/sh

# This script synchronizes a Git repository with a given Subversion repository.
# Originally specific to ImageJ2 (before that project switched over to Git),
# it accepts the repository URLs via the command-line, e.g. for use in a
# Jenkins job.
#
# It takes the Subversion URL as first parameter and an arbitrary number of
# Git push URLs after that.
#
# Example:
#
# git-svn-synchronizer.sh \
#	https://valelab.ucsf.edu/svn/micromanager2/ \
#	github.com:openspim/micromanager \
#	fiji.sc:/srv/git/micromanager1.4/.git \

usage () {
	echo "Usage: $0 [--force] [--reset] <Subversion-URL> <Git-push-URL>..." >&2
	exit 1
}

force=
reset=
while test $# -gt 0
do
	case "$1" in
	--force)
		force=--force
		;;
	--reset)
		git branch -D -r $(git branch -r)
		rm -rf .git/svn
		git config --remove-section svn-remote.svn
		reset=t
		;;
	-*)
		usage
		;;
	*)
		break
		;;
	esac
	shift
done

if test $# -lt 2
then
	usage
fi

set -e

SVN_URL="$1"
shift

# initialize repository
if ! test -d .git
then
	git init &&
	git config core.bare true &&
	if test -z "$reset"
	then
		git remote add -f tmp "$1" &&
		# read from remote repository to prevent unnecessary git-svn cloning
		git for-each-ref --format '%(refname)' refs/remotes/tmp/svn/ |
		while read ref
		do
			git push . $ref:refs/remotes/${ref#refs/remotes/tmp/svn/}
		done &&
		git remote rm tmp
	fi
fi

# initialize the Subversion URL
if ! test -d .git/svn || test "a${SVN_URL%/}" != "a$(git config svn-remote.svn.url)"
then
	# Try standard trunk/branches/tags setup first
	git svn init -s "$SVN_URL" &&
	git svn fetch &&
	git rev-parse refs/remotes/trunk ||
	git rev-parse refs/remotes/git-svn || {
		rm -rf .git/svn &&
		git config --remove-section svn-remote.svn &&
		git svn init "$SVN_URL" &&
		git svn fetch
	}
else
	git svn fetch
fi

# push refs/remote/* to refs/heads/svn/*
args="$(git for-each-ref --shell --format '%(refname)' refs/remotes/ |
	sed -e "s/^'\(refs\/remotes\/\(.*\)\)'$/'\1:refs\/heads\/svn\/\2'/" \
		-e 's/:refs\/heads\/svn\/tags\//:refs\/tags\//')"

git gc --auto
for remote
do
	eval git push $force \"$remote\" $args
done
