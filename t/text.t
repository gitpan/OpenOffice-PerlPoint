

# = HISTORY SECTION =====================================================================

# ---------------------------------------------------------------------------------------
# version | date     | author   | changes
# ---------------------------------------------------------------------------------------
# 0.01    |19.06.2005| JSTENZEL | new.
# ---------------------------------------------------------------------------------------

# an OpenOffice::PerlPoint test script

# pragmata
use strict;

# load modules
use Text::Diff;
use OpenOffice::PerlPoint;
use Test::More qw(no_plan);


# Open Office 1.0 format
{
 # build a converter object
 my $oo2pp=new OpenOffice::PerlPoint(file => 't/text.sxw');

 # convert document
 my $perlpoint=$oo2pp->oo2pp;

 # check result
 is(diff('t/text-sxw.pp', \$perlpoint), '', 'OO Text 1.0');
}


# Open Office 2.0 (OASIS Open Document) format
{
 local($TODO)="Open Document support is incomplete at the moment.";

 # build a converter object
 my $oo2pp=new OpenOffice::PerlPoint(file => 't/text.odt');

 # convert document
 my $perlpoint=$oo2pp->oo2pp;

 # check result
 is(diff('t/text-odt.pp', \$perlpoint), '', 'OASIS Open Document');
}

