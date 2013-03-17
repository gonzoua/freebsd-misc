#!/usr/bin/env perl

use strict;
use MetaCPAN::API;
use Data::Dumper;

# simple usage
my $mcpan  = MetaCPAN::API->new();

my $cmd = $ARGV[0];

my $makefile_template = q~
# New ports collection makefile for:	p5-%%DIST%%
# Date created:		20 February 2009
# Whom:	      		gonzo@freebsd.org
#
# $FreeBSD$
#

PORTNAME=	%%DIST%%
PORTVERSION=	%%VERSION%%
CATEGORIES=	bluezbox perl5
MASTER_SITES=	CPAN
PKGNAMEPREFIX=	p5-
DISTNAME=	${PORTNAME}-${PORTVERSION}

MAINTAINER=	gonzo@bluezbox.com
COMMENT=	Some obscure port

BUILD_DEPENDS=	

RUN_DEPENDS:=	${BUILD_DEPENDS}

PERL_CONFIGURE=	YES

# %%MAN3%%

.include <bsd.port.mk>
~;

if (@ARGV != 2) {
	usage();
	exit (1);
}

if ($cmd eq 'mkport') {
	my $dist_name = $ARGV[1];
	my $dist = $mcpan->release( distribution => $dist_name );
	# print Dumper($dist);
	die "Can't find dist info" if(!defined($dist));
	my $version = $dist->{version};
	mkdir "p5-$dist_name";
	my $makefile = $makefile_template;
	$makefile =~ s/%%DIST%%/$dist_name/g;
	$makefile =~ s/%%VERSION%%/$version/g;
	open F, "> p5-$dist_name/pkg-descr";
	print F "Bogus description for $dist_name";
	close F;

	open F, "> p5-$dist_name/Makefile";
	print F $makefile;
	close F;
	chdir("p5-$dist_name");
	system("make makesum");
}
elsif ($cmd eq 'fixup') {
	my $prefix = $ARGV[1];
	system("make install PREFIX=$prefix");
	my $output = `find $prefix -type f`;
	my @files = split /\n/, $output;
	my @mans;
	my @plist;
	my %dirs;
	foreach my $file (@files) {
		if ($file =~ /\.3$/) {
			my $man = $file;
			$man =~ s/.*\///;
			push @mans, $man;
		}
		else {
			if ($file =~ s/.*site_perl\/[\d\.]+/%%SITE_PERL%%/) {
				push @plist, $file;
				my $dir = $file;
				$dir =~ s/\/[^\/]+$//;
				$dirs{$dir} = 1;
			}
			else {
				print "--> $file ?\n";
			}
		}
	}

	push @plist, '';
	foreach my $d (sort {$a cmp $b} keys %dirs) {
		push @plist, "\@dirrmtry " . $d;
	}

	open F, "> pkg-plist";
	print F join "\n", @plist;
	close F;

	open F, "> man3";
	print F join "\t\t", @mans;
	close F;

	system("make deinstall PREFIX=$prefix");
}
else {
	usage();
	exit (1);
}

sub usage
{
	print STDERR "mk_cpan_port.pl cmd arg\n";
	print STDERR "    mkport Distribution-Name\tCreate skeleton port for Distribution-Name\n";
	print STDERR "    fixup /tmp/prefix\t\tfixup plist file using temporary prefix\n";
}
