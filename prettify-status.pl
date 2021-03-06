#!/usr/bin/perl

# prettify-status.pl - converts plaintext status to HTML.
#
# Usage: prettify-status.pl < status.txt > status.html

use strict;

my %orgs = (
  'org.scijava' => 'scijava',
  'io.scif'     => 'scifio',
  'net.imagej'  => 'imagej',
  'net.imglib2' => 'imglib',
  'sc.fiji'     => 'fiji',
);

sub rowClass($$) {
  my $index = shift;
  my $count = shift;
  my $rowClass = $index % 2 == 0 ? 'even' : 'odd';
  if ($index == 0) { $rowClass .= ' first'; }
  if ($index == $count - 1) { $rowClass .= ' last'; }
  return $rowClass;
}

# parse status output
my @unknown = ();
my @ahead = ();
my @released = ();
my @warnings = ();

my @lines = <>;

for my $line (sort @lines) {
  chomp $line;
  if ($line =~ /([^:]+):([^:]+): (\d+)\/(\d+) commits on (\w+) since (.*)/) {
    my $groupId = $1;
    my $artifactId = $2;
    my $commitCount = $3;
    my $totalCommits = $4;
    my $branch = $5;
    my $version = $6;
    my $tag = $version ? "$artifactId-$version" : "";
    my $org = $orgs{$groupId};
    if (!$org) { $org = $groupId; }
    my $repo = $artifactId;
    $repo =~ s/_$//;
    my $link = "https://github.com/$orgs{$groupId}/$repo";

    my $data = {
      groupId      => $groupId,
      artifactId   => $artifactId,
      commitCount  => $commitCount,
      totalCommits => $totalCommits,
      branch       => $branch,
      version      => $version,
      tag          => $tag,
      org          => $org,
      repo         => $repo,
    };

    if (not $org) {
      my $warning = { %$data };
      $warning->{line} = "No known GitHub org for groupId '$groupId'\n";
      push @warnings, $warning;
    }

    if (!$version) {
      # release status is unknown
      $data->{line} = "<td class=\"first\"></td>\n" .
        "<td><a href=\"$link\">$artifactId</a></td>\n";
      push @unknown, $data;
    }
    elsif ($commitCount > 0) {
      # a release is needed
      $data->{line} = "<td class=\"first\"></td>\n" .
        "<td><a href=\"$link\">$artifactId</a></td>\n" .
        "<td><a href=\"$link/compare/$tag...$branch\">$commitCount/$totalCommits</a></td>\n" .
        "<td><a href=\"$link/tree/$tag\">$version</a></td>\n";
      push @ahead, $data;
    }
    else {
      # everything is up to date
      my $tagLink = $tag ? "<a href=\"$link/tree/$tag\">$version</a>" : "-";
      $data->{line} = "<td class=\"first\"></td>\n" .
        "<td><a href=\"$link\">$artifactId</a></td>\n" .
        "<td>$tagLink</td>\n";
      push @released, $data;
    }
  }
  else {
    my $data = {};
    $data->{line} = $line;
    push @warnings, $data;
  }
}

# dump prettified version

print <<HEADER;
<html>
<head>
<title>SciJava software status</title>
<link type="text/css" rel="stylesheet" href="status.css" />
<link rel="icon" type="image/png" href="favicon.png" />
<script type="text/javascript" src="http://code.jquery.com/jquery.js"></script>
<script type="text/javascript">
  \$(document).ready(function() {
    \$('input[type="checkbox"]').click(function() {
      \$("." + \$(this).attr("value")).toggle();
    });
  });
</script>
</head>
<body>
HEADER

print "<div class=\"toggles\">\n";
print "<h2>Projects</h2>\n";
print "<ul>\n";
for my $org (sort values %orgs) {
  print "<li><input type=\"checkbox\" value=\"$org\" checked>$org</li>\n";
}
print "</ul>\n";
print "</div>\n";

if (@warnings > 0) {
  print "<div class=\"warnings\">\n";
  print "<h2>Warnings</h2>\n";
  print "<ul class=\"warnings\">\n";
  my $rowIndex = 0;
  my $rowCount = @warnings;
  for my $row (@warnings) {
    my $org = $row->{org};
    my $line = $row->{line};
    my $rowClass = rowClass($rowIndex++, $rowCount);
    print "<li class=\"$org $rowClass\">\n$line\n</li>\n";
  }
  print "</ul>\n";
  print "</div>\n\n";
}

if (@released > 0) {
  print "<div class=\"released\">\n";
  print "<h2>Released</h2>\n";
  print "<table>\n";
  print "<tr>\n";
  print "<th>&nbsp;</th>\n";
  print "<th>Project</th>\n";
  print "<th>Latest version</th>\n";
  print "</tr>\n";
  my $lastGroupId = '';
  my $rowIndex = 0;
  my $rowCount = @released;
  for my $row (@released) {
    my $org = $row->{org};
    my $groupId = $row->{groupId};
    if ($lastGroupId ne $groupId) {
      print "<tr class=\"$org\">\n";
      print "<td class=\"section\" colspan=4>" .
        "<a href=\"https://github.com/$org\">$org</a></td>\n";
      print "</tr>\n";
      $lastGroupId = $groupId;
    }
    my $line = $row->{line};
    my $rowClass = rowClass($rowIndex++, $rowCount);
    print "<tr class=\"$org $rowClass\">\n$line</tr>\n";
  }
  print "</table>\n";
  print "</div>\n\n";
}

if (@unknown > 0) {
  print "<div class=\"unknown\">\n";
  print "<h2>Unknown</h2>\n";
  print "<table>\n";
  print "<tr>\n";
  print "<th>&nbsp;</th>\n";
  print "<th>Project</th>\n";
  print "</tr>\n";
  my $lastGroupId = '';
  my $rowIndex = 0;
  my $rowCount = @unknown;
  for my $row (@unknown) {
    my $org = $row->{org};
    my $groupId = $row->{groupId};
    if ($lastGroupId ne $groupId) {
      print "<tr class=\"$org\">\n";
      print "<td class=\"section\" colspan=2>" .
        "<a href=\"https://github.com/$org\">$org</a></td>\n";
      print "</tr>\n";
      $lastGroupId = $groupId;
    }
    my $line = $row->{line};
    my $rowClass = rowClass($rowIndex++, $rowCount);
    print "<tr class=\"$org $rowClass\">\n$line</tr>\n";
  }
  print "</table>\n";
  print "</div>\n\n";
}

if (@ahead > 0) {
  print "<div class=\"ahead\">\n";
  print "<h2>Ahead</h2>\n";
  print "<table>\n";
  print "<tr>\n";
  print "<th>&nbsp;</th>\n";
  print "<th>Project</th>\n";
  print "<th>Commits</th>\n";
  print "<th>Latest version</th>\n";
  print "</tr>\n";
  my $lastGroupId = '';
  my $rowIndex = 0;
  my $rowCount = @ahead;
  for my $row (@ahead) {
    my $org = $row->{org};
    my $groupId = $row->{groupId};
    if ($lastGroupId ne $groupId) {
      print "<tr class=\"$org\">\n";
      print "<td class=\"section\" colspan=4>" .
        "<a href=\"https://github.com/$org\">$org</a></td>\n";
      print "</tr>\n";
      $lastGroupId = $groupId;
    }
    my $line = $row->{line};
    my $rowClass = rowClass($rowIndex++, $rowCount);
    print "<tr class=\"$org $rowClass\">\n$line</tr>\n";
  }
  print "</table>\n";
  print "</div>\n\n";
}

print "<div class=\"links\">\n";
print "<h2>See also</h2>\n";
print "<ul>\n";
print "<li><a href=\"https://github.com/imagej/imagej/blob/master/RELEASES.md\">ImageJ RELEASES.md</a></li>\n";
print "<li><a href=\"http://jenkins.imagej.net/job/Release-Version/\">Release-Version Jenkins job</a></li>\n";
print "</ul>\n";
print "</div>\n\n";

print "<div class=\"footer\">&nbsp;</div>\n\n";

print "</body>\n";
print "</html>\n";
