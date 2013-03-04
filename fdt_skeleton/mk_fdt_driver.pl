#!/usr/bin/perl -w

use strict;
use warnings;

use YAML;
use Data::Dumper;

if (@ARGV != 1) {
	print "Usage: mk_fdt_driver.pl config.yml\n";
	exit(1);
}
undef $/;
open F, "< $ARGV[0]";
my $data = <F>;
close F;

# load YAML file into perl hash ref?
my $config = Load($data);

# snippets 
my $license = <<__EOLICENSE__;
/*-
 * Copyright (c) %YEAR% %AUTHOR%
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

__EOLICENSE__

my $includes = <<__EOINCLUDES__;
#include <sys/cdefs.h>
__FBSDID("\$FreeBSD\$");

#include <sys/param.h>
#include <sys/systm.h>
#include <sys/kernel.h>
#include <sys/module.h>
#include <sys/bus.h>
#include <sys/lock.h>
#include <sys/mutex.h>
#include <sys/resource.h>
#include <sys/rman.h>

#include <machine/bus.h>

#include <dev/ofw/openfirm.h>
#include <dev/ofw/ofw_bus.h>
#include <dev/ofw/ofw_bus_subr.h>

__EOINCLUDES__

my $defines = <<__EODEFINES__;
#define	%MACRO_PREFIX%_LOCK(_sc)		mtx_lock(&(_sc)->sc_mtx)
#define	%MACRO_PREFIX%_UNLOCK(_sc)		mtx_unlock(&(_sc)->sc_mtx)
#define	%MACRO_PREFIX%_LOCK_INIT(_sc)	mtx_init(&(_sc)->sc_mtx, \\
    device_get_nameunit(_sc->sc_dev), "%DRIVER% softc", MTX_DEF)
#define	%MACRO_PREFIX%_LOCK_DESTROY(_sc)	mtx_destroy(&(_sc)->sc_mtx);

#define	%MACRO_PREFIX%_READ4(_sc, reg)	bus_read_4((_sc)->sc_mem_res, reg);
#define	%MACRO_PREFIX%_WRITE4(_sc, reg, value)	\\
    bus_write_4((_sc)->sc_mem_res, reg, value);

__EODEFINES__

my $softc = <<__EOSOFTC__;

static device_probe_t %PREFIX%_probe;
static device_attach_t %PREFIX%_attach;
static device_detach_t %PREFIX%_detach;

struct %PREFIX%_softc {
	device_t		sc_dev;
	struct mtx		sc_mtx;
__EOSOFTC__

my $bus_methods = <<__EOMETHODS__;
static int
%PREFIX%_probe(device_t dev)
{
	if (!ofw_bus_is_compatible(dev, "%FDT_COMPATIBLE%"))
		return (ENXIO);

	device_set_desc(dev, "TODO: Add description");

	return (BUS_PROBE_DEFAULT);
}

static int
%PREFIX%_attach(device_t dev)
{
	struct %PREFIX%_softc *sc;
	int rid, err;

	sc = device_get_softc(dev);
	sc->sc_dev = dev;
	%MACRO_PREFIX%_LOCK_INIT(sc);

%INIT_SECTION%
}

static int
%PREFIX%_detach(device_t dev)
{
	struct %PREFIX%_softc *sc;
	int rid;

	sc = device_get_softc(dev);
	%MACRO_PREFIX%_LOCK_DESTROY(sc);

%DESTROY_SECTION%
}

static device_method_t %DRIVER%_methods[] = {
	DEVMETHOD(device_probe,		%PREFIX%_probe),
	DEVMETHOD(device_attach,	%PREFIX%_attach),
	DEVMETHOD(device_detach,	%PREFIX%_detach),

	DEVMETHOD_END
};

static driver_t %DRIVER%_driver = {
	"%DRIVER%",
	%PREFIX%_methods,
	sizeof(struct %PREFIX%_softc),
};

static devclass_t %DRIVER%_devclass;

DRIVER_MODULE(%DRIVER%, simplebus, %DRIVER%_driver, %DRIVER%_devclass, 0, 0);
MODULE_VERSION(%DRIVER%, 1);
MODULE_DEPEND(%DRIVER%, simplebus, 1, 1, 1);
__EOMETHODS__

# Resources 
my $mem_resources = $config->{MEM_RESOURCES} || 0;
my $irq_resources = $config->{IRQ_RESOURCES} || 0;

my $file = $license;
$file .= $includes;
$file .= $defines;

my $specs = '';

if ($mem_resources > 1) {
	$specs .= generate_specs($mem_resources, 'mem', 'SYS_RES_MEMORY');
}

if ($irq_resources > 1) {
	$specs .= generate_specs($irq_resources, 'irq', 'SYS_RES_IRQ');
}

$file .= $specs;

# Generate proper softc
$file .= $softc;

if ($mem_resources == 1) {
    $file .= "\tstruct resource\t\t*sc_mem_res;\n";
}
elsif ($mem_resources > 1) {
    $file .= "\tstruct resource\t\t*sc_mem_res[$mem_resources];\n";
}

if ($irq_resources == 1) {
    $file .= "\tstruct resource\t\t*sc_irq_res;\n";
    $file .= "\tvoid\t\t\t*sc_intr_hl;\n";
}
elsif ($irq_resources > 1) {
    $file .= "\tstruct resource\t\t*sc_irq_res[$irq_resources];\n";
    $file .= "\tvoid\t\t\t*sc_intr_hl[$irq_resources];\n";
}

$file .= "};\n\n";

my $init_section = generate_init_section($mem_resources, $irq_resources);
my $destroy_section = generate_destroy_section($mem_resources, $irq_resources);

$file .= $bus_methods;

my $macro_prefix = $config->{MACRO_PREFIX};
$macro_prefix = uc($config->{PREFIX}) unless (defined($macro_prefix));

my @localt = localtime(time);
my $year = $localt[5] + 1900;

$file =~ s/%INIT_SECTION%/$init_section/;
$file =~ s/%DESTROY_SECTION%/$destroy_section/;
$file =~ s/%DRIVER%/$config->{DRIVER}/g;
$file =~ s/%PREFIX%/$config->{PREFIX}/g;
$file =~ s/%YEAR%/$year/g;
$file =~ s/%AUTHOR%/$config->{AUTHOR}/g;
$file =~ s/%MACRO_PREFIX%/$macro_prefix/g;
$file =~ s/%FDT_COMPATIBLE%/$config->{FDT_COMPATIBLE}/g;

print $file;

#
# Helper routines
#

sub generate_init_section
{
	my ($mres, $ires) = @_;
	my $sec = '';
	my $fail_sec = "fail:\n\t%MACRO_PREFIX%_LOCK_DESTROY(sc);\n";

	return "\treturn (0);" if (($mres == 0) && ($ires == 0));
	
	if ($mres == 1) {
		$sec .= <<__EOALLOC__;
	rid = 0;
	sc->sc_mem_res = bus_alloc_resource_any(dev, SYS_RES_MEMORY, &rid,
	    RF_ACTIVE);
	if (!sc->sc_mem_res) {
		device_printf(dev, "cannot allocate memory resource\\n");
		goto fail;
	}

__EOALLOC__
	}

	if ($mres > 1) {
		$sec .= <<__EOALLOC__;
	err = bus_alloc_resources(dev, %PREFIX%_mem_spec,
	    sc->sc_mem_res);
	if (err) {
		device_printf(dev, "cannot allocate memory resources\\n");
		goto fail;
	}

__EOALLOC__
	}


	if ($ires == 1) {
		$sec .= <<__EOALLOC__;
	rid = 0;
	sc->sc_irq_res = bus_alloc_resource_any(dev, SYS_RES_IRQ, &rid,
	    RF_ACTIVE);
	if (!sc->sc_irq_res) {
		device_printf(dev, "cannot allocate IRQ resource\\n");
		goto fail;
	}
__EOALLOC__
	}

	if ($ires > 1) {
		$sec .= <<__EOALLOC__;
	err = bus_alloc_resources(dev, %PREFIX%_irq_spec,
	    sc->sc_irq_res);
	if (err) {
		device_printf(dev, "cannot allocate IRQ resources\\n");
		goto fail;
	}

__EOALLOC__
	}

	# Both memory and IRQ resources, memory always initialized first
	# so release it and don't care for IRQ
	if ($mres && $ires) {
		if ($mres == 1) {
			$fail_sec .= <<__EOFAIL__;
	rid = 0;
	if (sc->sc_mem_res)
		bus_release_resource(dev, SYS_RES_MEMORY,
		    rid, sc->sc_mem_res);
__EOFAIL__
		}
		if ($mres > 1) {
			$fail_sec .= <<__EOMRELEASE1__;
	if (sc->sc_mem_res[0])
		bus_release_resources(dev, %PREFIX%_mem_spec,
		    sc->sc_mem_res);
__EOMRELEASE1__
		}
	}

	$sec .= "\n\treturn (0);\n";

	$fail_sec .= "\n\treturn(ENXIO);";

	return $sec . $fail_sec;
}

sub generate_destroy_section
{
	my ($mres, $ires) = @_;
	my $sec = '';

	if ($mres == 1) {
		$sec .= <<__EOMRELEASE1__;
	rid = 0;
	if (sc->sc_mem_res)
		bus_release_resource(dev, SYS_RES_MEMORY,
		    rid, sc->sc_mem_res);
__EOMRELEASE1__
	}

	if ($ires == 1) {
		$sec .= <<__EOIRELEASE1__;
	rid = 0;
	if (sc->sc_irq_res)
		bus_release_resource(dev, SYS_RES_IRQ,
		    rid, sc->sc_irq_res);
__EOIRELEASE1__
	}

	if ($mres > 1) {
		$sec .= <<__EOMRELEASE1__;
	if (sc->sc_mem_res[0])
		bus_release_resources(dev, %PREFIX%_mem_spec,
		    sc->sc_mem_res);
__EOMRELEASE1__
	}

	if ($ires > 1) {
		$sec .= <<__EOMRELEASE1__;
	if (sc->sc_irq_res[0])
		bus_release_resources(dev, %PREFIX%_irq_spec,
		    sc->sc_irq_res);
__EOMRELEASE1__
	}

	$sec .= "\n\treturn (0);";
	return $sec;
}


sub generate_specs
{
	my ($nres, $name, $type) = @_;
	my $spec = <<__EOSPEC__;
static struct resource_spec %PREFIX%_${name}_spec[] = {
__EOSPEC__
	for (my $i = 0; $i < $nres; $i++) {
		$spec .= "\t{ $type, $i, RF_ACTIVE },\n";
	}
	$spec .= "\t{ -1, 0, 0 }\n};\n";
	return $spec;
}
