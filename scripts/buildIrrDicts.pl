#!/usr/bin/perl

use strict;

if($#ARGV < 1) {
  die "Usage: buildIrrDicts.pl <v|n> <word-list-file>";
}

my $file = $ARGV[1];
my $type = $ARGV[0];

open(FILE, "<$file");
open(KEYS, ">keys.$type");
open(DICT, ">dict.$type");

my $line = "";
my $lineno = 0;

my %keyMap = ();

while($line = <FILE>) {
  $lineno++;
  chomp($line);
  my @toks = split(/\s/, $line);

  my $lst = "[";
  for(my $i=0; $i<=$#toks; $i++) {
    my $t = $toks[$i];
    if($i > 0) {
      $lst .= ", ";
    }
    $lst .= "'$t'";
    if(!exists $keyMap{$t}) {
      $keyMap{$t} = ();
    }
    push(@{ $keyMap{$t} }, $lineno);
  }
  $lst .= "]";
  if($lineno > 1) {
    print DICT ", ";
  }
  print DICT "$lineno: $lst";
}

close DICT;

my $keyStr = "";
for my $k (keys %keyMap) {
  my $str = join(", ", @{ $keyMap{$k} });
  $keyStr .= "'$k': [".join(", ", @{ $keyMap{$k} })."], "; 
}
$keyStr =~ s/, $//g;

print KEYS $keyStr;

close KEYS
