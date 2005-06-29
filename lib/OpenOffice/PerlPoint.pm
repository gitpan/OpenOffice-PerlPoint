
# = HISTORY SECTION =====================================================================

# ---------------------------------------------------------------------------------------
# version | date     | author   | changes
# ---------------------------------------------------------------------------------------
# 0.01    |19.06.2005| JSTENZEL | First version, derived from a oo2pod example in
#         |          |          | OpenOffice::OODoc 1.309.
# ---------------------------------------------------------------------------------------

# = POD SECTION =========================================================================

=head1 NAME

B<OpenOffice::PerlPoint> - an Open Office / Open Document to PerlPoint converter class

=head1 VERSION

This manual describes version B<0.01>.

=head1 SYNOPSIS

 # load the module
 use OpenOffice::PerlPoint;

 # build an object
 my $oo2pp=new OpenOffice::PerlPoint(file=>$ooFile);

 # convert document
 my $perlpoint=$oo2pp->oo2pp;


=head1 DESCRIPTION

C<OpenOffice::PerlPoint> is a translator class to transform Open Office 1.0 and 2.0 (and
generally OASIS Open Document) documents into PerlPoint sources. It is based on
C<OpenOffice::OODoc>.

Once you have transformed an Open Office or Open Document document into PerlPoint, it may
be furtherly processed using the PerlPoint utilities.

If you prefer, you do not need to perform an explicit transformation. Beginning with
release 0.40, C<PerlPoint::Package> can process Open Office / Open Document sources directly.
Please see C<PerlPoint::Parser> for details, or the documentation that comes with PerlPoint.

B<This software is in alpha state. It supports just a I<subset> of the source format features.>
Please see the I<NOTES> sections below.

=head1 METHODS

=cut


# declare package
package OpenOffice::PerlPoint;

# declare version
$VERSION=0.01;

# pragmata
use strict;

# load modules
use Carp;
use Text::Wrapper;
use File::Basename;
use OpenOffice::OODoc;

# declare attributes
use fields qw(
              file
              archive
              metadata
              docContent
              docStyles
              content
              notes
             );


# define data: delimiter handling
my %delimiters=(
                'text:footnote-citation' => {
                                             begin => '[',
                                             end   => ']',
                                            },
                'text:footnote-body'     => {
                                             begin => '{NOTE: ',
                                             end   => '}',
                                            },
                'text:span'              => {
                                             begin => '<<',
                                             end   => '>>',
                                            },
                'text:list-item'         => {
                                             begin => '',
                                             end   => '',
                                            },
               );


# define data: style extraction directives for traversal (see traverseElement() below)
my @styles=(
            ['B',     'properties', 'fo:font-weight', 'bold', 0, '\B<', '>'],
            ['I',     'properties', 'fo:font-style', 'italic', 0, '\I<', '>'],
            ['U',     'properties', 'style:text-underline', 'single', 0, '\U<', '>'],                # OO 1.0
            ['U',     'properties', 'style:text-underline-style', 'solid', 0, '\U<', '>'],           # OD (missing the previous part -bug?!)
            ['F',     'properties', 'fo:color', qr/^(\#[\da-fA-F]{6})$/, 0, '\F{color="$1"}<', '>'], # first backslash is for highlightning
            ['C',     'properties', 'style:font-name', qr/^(Courier New)$/, 0, '\C<', '>'],
            ['BLOCK', 'references', 'style:parent-style-name', qr/^(Code)$/, 0, ' ' x 3, ''],
           );



# init wrappers
my ($paragraphWrapper, $listWrapper);
$paragraphWrapper=Text::Wrapper->new(
                                     columns	=> 76,
                                     par_start	=> '',
                                     body_start	=> ''
                                    );
  
$listWrapper=Text::Wrapper->new(
                                columns		=> 76,
                                par_start	=> '  ',
                                body_start	=> '  '
                               );

=pod

=head2 new()

The constructor.

B<Parameters:>

All parameters except the first are named.

=over 4

=item class

The target class name. This parameter is set automatically if you use the usual Perl syntax
to call a constructor.

=item file

The (absolute or relative) path to the Office document that should be converted.

=back

B<Returns:> the new object.

B<Example:>

 # build an object
 my $oo2pp=new OpenOffice::PerlPoint(file=>$ooFile);

=cut
sub new
 {
  # get parameters
  my ($class, @pars)=@_;

  # build parameter hash
  confess "[BUG] The number of parameters should be even - use named parameters, please.\n" if @pars%2;
  my %pars=@pars;

  # check parameters
  confess "[BUG] Missing class name.\n" unless $class;
  confess "[BUG] Missing file parameter.\n" unless exists $pars{file};

  # build object
  my __PACKAGE__ $me=fields::new($class);

  # store filename
  $me->{file}=$pars{file};

  # build archive object
  $me->{archive}=ooFile($pars{file});
  confess "[Error] $pars{file} is no regular OpenOffice.org file.\n" unless $me->{archive};

  # extract metadata
  $me->{metadata}=ooMeta(archive => $me->{archive});
  carp "[Warn] $pars{file} has not standard OOO properties, it looks strange.\n" unless $me->{metadata};

  # extract document (in content and style parts)
  $me->{docContent}=ooDocument(
                               archive    => $me->{archive},
                               member     => 'content',
                               delimiters => \%delimiters,
                              );
  confess "[Error] No standard OOO content found in $pars{file}!\n" unless $me->{docContent};

  $me->{docStyles}=ooDocument(
                              archive    => $me->{archive},
                              member     => 'styles',
                              delimiters => \%delimiters,
                             );
  confess "[Error] No standard OOO styles found in $pars{file}!\n" unless $me->{docContent};

  # the strange next lines prevent the getText() method of
  # OpenOffice::OODoc::Text (see the corresponding man page) from using
  # its default tags for spans and footnotes
  delete $me->{docContent}{delimiters}{'text:span'};
  delete $me->{docContent}{delimiters}{'text:footnote-body'};

  # here we select the tab as field separator for table field output
  # (the default is ";" as for CSV output)
  $me->{docContent}{field_separator}="\t";

  # in the next sequence, we will extract all the footnotes, store them for
  # later processing and remove them from the content
  $me->{notes}=[$me->{docContent}->getFootnoteList];
  $me->{docContent}->removeElement($_) for @{$me->{notes}};

  # get the full list of text objects (without the previously removed footnotes)
  $me->{content}=[$me->{docContent}->getTextElementList];

  # reply the new object
  $me;
 }

# TODO: make document variable names configurable
sub convertMetadata
 {
  # get and check parameters
  ((my __PACKAGE__ $me), (my ($item, $guard)))=@_;
  confess "[BUG] Missing object parameter.\n" unless $me;
  confess "[BUG] Object parameter is no ", __PACKAGE__, " object.\n" unless ref $me and ref $me eq __PACKAGE__;

  # variables
  my ($perlpoint, $title, $subject, $description, $author, $date, $version, $generator, $copyright);

  # anything to do?
  if ($me->{metadata})
	{
     # introductory comment
     $perlpoint=join('', defined $perlpoint ? $perlpoint : "\n", $me->constructComment('-' x 60), "\n", $me->constructComment('set document data'));

     # title
     $title=$me->{metadata}->title;
     $perlpoint.="\$docTitle=$title\n\n" if $title;
     $title='unknown' unless $title;

     # subject
     $subject=$me->{metadata}->subject;
     $perlpoint.="\$docSubtitle=$subject\n\n" if $subject;
     $subject='unknown' unless $subject;

     # description
     $description=$me->{metadata}->description;
     $perlpoint.="\$docDescription=$description\n\n" if $description;
     $description='unknown' unless $description;

     # author
     $author=$me->{metadata}->creator;
     $perlpoint.="\$docAuthor=$author\n\n" if $author;
     $author='unknown' unless $author;

     # date
     $date=$me->{metadata}->date;
     $perlpoint.="\$docDate=$title\n\n" if $date;
     $date='unknown' unless $date;

     # get user defined metadata
     my %userDefinedMetadata=$me->{metadata}->user_defined;

     # version, if available
     $version=$userDefinedMetadata{version} if exists $userDefinedMetadata{version};
     $perlpoint.="\$docVersion=$version\n\n" if $version;
     $version='unknown' unless $version;

     # copyright, if available
     $copyright=$userDefinedMetadata{copyright} if exists $userDefinedMetadata{copyright};
     $perlpoint.="\$docCopyright=$copyright\n\n" if $copyright;
     $copyright='unknown' unless $copyright;

     # complete section
     $perlpoint=join('', $perlpoint, $me->constructComment('-' x 60), "\n");

     # get generator
     $generator=$me->{metadata}->generator;
     $generator='unknown program' unless $generator;
	}

  # add a header comment with description, format, author, version etc.
  $perlpoint=join('', <<EOI, $perlpoint);

// document description, packed into a condition for readability
? 0

 Description: $description

 Format:      This file is written in PerlPoint (www.sf.net/projects/perlpoint).
              It can be translated into several documents and formats, see the
              PerlPoint documentation for details.

              The original source of this document was stored by
              $generator.

              It was converted into PerlPoint by ${\(__PACKAGE__)}.

 Source:      $me->{file}.

 Author:      $author

 Copyright:   $copyright

 Version:     $version

// start document
? 1

EOI

  # supply result
  $perlpoint;
 }


#-----------------------------------------------------------------------------

# convert completely (TODO: make certain steps like meta data conversion optional)
=pod

=head2 oo2pp()

Perform conversion of the document specified in the constructor call.

B<Parameters:>

=over 4

=item object

A object as supplied by C<new()>.

=back

B<Returns:> the PerlPoint string.

B<Example:>

 # convert document
 my $perlpoint=$oo2pp->oo2pp;

=cut
sub oo2pp
 {
  # get and check parameters
  ((my __PACKAGE__ $me), (my ($item, $guard)))=@_;
  confess "[BUG] Missing object parameter.\n" unless $me;
  confess "[BUG] Object parameter is no ", __PACKAGE__, " object.\n" unless ref $me and ref $me eq __PACKAGE__;

  # variables
  my ($perlpoint);

  # meta data
  $perlpoint.=$me->convertMetadata;

  # content
  $perlpoint.=$me->convertContent;

  # supply result
  $perlpoint;
 }

#-----------------------------------------------------------------------------

# build a headline
sub buildHeadline
 {
  # get and check parameters
  my ($me, $element)=@_;
  confess "[BUG] Missing object parameter.\n" unless $me;
  confess "[BUG] Object parameter is no ", __PACKAGE__, " object.\n" unless ref $me and ref $me eq __PACKAGE__;
  confess "[BUG] Missing element parameter.\n" unless defined $element;
  confess "[BUG] Element parameter is no ", 'XML::Twig::Elt', " object.\n" unless ref $element and $element->isa('XML::Twig::Elt');

  # build headline and supply result
  $me->constructHeadline($me->{docContent}->getLevel($element), $me->{docContent}->getText($element) || 'EMPTY HEADLINE FOUND - CHECK SOURCE DOCUMENT FORMATTING, PLEASE ~ EMPTY HEADLINE');
 }

#-----------------------------------------------------------------------------

# a low level routine to build a headline
sub constructHeadline
 {
  # get and check parameters
  ((my __PACKAGE__ $me), (my ($level, $text, $short)))=@_;
  confess "[BUG] Missing object parameter.\n" unless $me;
  confess "[BUG] Object parameter is no ", __PACKAGE__, " object.\n" unless ref $me and ref $me eq __PACKAGE__;
  confess "[BUG] Missing level parameter.\n" unless defined $level;
  confess "[BUG] Missing text parameter.\n" unless $text;

  # build headline and supply result
  join('', '=' x $level, $text, (defined $short ? " ~ $short" : ()), "\n\n");
 }

#-----------------------------------------------------------------------------

# a low level routine to build a comment
sub constructComment
 {
  # get and check parameters
  ((my __PACKAGE__ $me), (my ($text)))=@_;
  confess "[BUG] Missing object parameter.\n" unless $me;
  confess "[BUG] Object parameter is no ", __PACKAGE__, " object.\n" unless ref $me and ref $me eq __PACKAGE__;
  confess "[BUG] Missing text parameter.\n" unless $text;

  # build comment and supply result
  join('', '// ', $text, "\n");
 }

#-----------------------------------------------------------------------------

# build a separate note section (at the end of the document)
sub	buildNoteBlock
 {
  # get and check parameters
  my ($me)=@_;
  confess "[BUG] Missing object parameter.\n" unless $me;
  confess "[BUG] Object parameter is no ", __PACKAGE__, " object.\n" unless ref $me and ref $me eq __PACKAGE__;

 }

#-----------------------------------------------------------------------------

# build content from element
sub buildContent
 {
  # get and check parameters
  my ($me, $element)=@_;
  confess "[BUG] Missing object parameter.\n" unless $me;
  confess "[BUG] Object parameter is no ", __PACKAGE__, " object.\n" unless ref $me and ref $me eq __PACKAGE__;
  confess "[BUG] Missing element parameter.\n" unless defined $element;
  confess "[BUG] Element parameter is no ", 'XML::Twig::Elt', " object.\n" unless ref $element and $element->isa('XML::Twig::Elt');

  # variables
  my ($perlpoint)=('');

  # get element text
  my $text=$me->{docContent}->getText($element);

  # choose an output format according to the type
  if ($element->isItemList)
   {
    # try to find out whether this list is ordered or not
    my $prefix=$element->isOrderedList ? '#' : '*';

    # handle all list elements
    foreach my $item ($me->{docContent}->getItemElementList($element))
     {
      # transform text
      my $transformed=$listWrapper->wrap($me->traverseElement($item, \&guardSpecials));

      # write it, if necessary
      $perlpoint.=$transformed ? ("$prefix $transformed\n") : ();
     }
   }
  elsif ($element->isTable)
   {
    # a table: get a table handle, table dimensions and the table text
    my $table=$me->{docContent}->getTable($element);
    my ($rowNr, $colNr)=$me->{docContent}->getTableSize($table);
    my $tableText=$me->{docContent}->getTableText($table);

    # set column separator
    my $columnSeparator='|';
    {
     my ($i, $cs)=(1, $columnSeparator);
     ++$i, $cs=quotemeta($columnSeparator='|' x $i) while $tableText=~/$cs/g;
    }
      
    # start table (TODO: switch to nested tables)
    $perlpoint.="\@$columnSeparator\n";

    # handle all rows
    foreach my $row ($me->{docContent}->getTableRows($table))
     {
      # cell value collector
      my (@cellValues);

      # handle all cells
      foreach my $cellNr (0..$colNr-1)
       {
        # get cell handle
        my $cell=$me->{docContent}->getCell($row, $cellNr);

        # get content
        push(@cellValues, $me->{docContent}->getCellValue($cell));
       }

      # add row
      $perlpoint=join('', $perlpoint, join(" $columnSeparator ", map {(defined) ? $_ : ''} @cellValues), "\n");
     }

    # complete table
    $perlpoint.="\n";
   }
  else
   {
    # scopies
    my ($empty, $prefix, $suffix)=('');

    # get paragraph style and its attributes
    my $styleName=$me->{docContent}->getStyle($element);
    my $styleObject=$me->{docContent}->getStyleElement($styleName) || $me->{docStyles}->getStyleElement($styleName);
    my %attributes=$me->{docContent}->getStyleAttributes($styleObject);

    # set paragraph prefix
    if (
            exists $attributes{references}{'style:family'}
        and $attributes{references}{'style:family'} eq 'paragraph'
        and exists $attributes{references}{'style:parent-style-name'}
        and $attributes{references}{'style:parent-style-name'}=~/^(Code)$/
       )
     {
      # a code block
      $prefix=' ' x 3;
      $suffix='';
      $empty="\n";
     }
    else
     {
      # default to a text paragraph
      $prefix='.';
      $suffix="\n";
     }

    # transform text
    my $transformed=$paragraphWrapper->wrap($me->traverseElement($element, \&guardSpecials));

    # write it, if necessary
    $perlpoint.=$transformed ? ("$prefix$transformed$suffix") : $empty;
   }

  # supply result
  $perlpoint;
 }

#-----------------------------------------------------------------------------

# convert content
sub	convertContent
 {
  # get and check parameters
  my ($me)=@_;
  confess "[BUG] Missing object parameter.\n" unless $me;
  confess "[BUG] Object parameter is no ", __PACKAGE__, " object.\n" unless ref $me and ref $me eq __PACKAGE__;

  # variables
  my ($perlpoint)=('');

  # handle all elements
  foreach my $element (@{$me->{content}})
   {
    # get element level
	if ($element->isHeader)
     {$perlpoint.=$me->buildHeadline($element);}
	else
     {$perlpoint.=$me->buildContent($element);}
   }

  # supply result
  $perlpoint;
 }

#-----------------------------------------------------------------------------


# Traverse an element to find style based formattings and produce appropriate markup.
# This is a proof of concept and needs cleanup (constants for indices etc.).
# The base traversal idea was taken from getText().
sub traverseElement
 {
  # get and check parameters
  ((my __PACKAGE__ $me), (my ($item, $guard)))=@_;
  confess "[BUG] Missing object parameter.\n" unless $me;
  confess "[BUG] Object parameter is no ", __PACKAGE__, " object.\n" unless ref $me and ref $me eq __PACKAGE__;
  confess "[BUG] Guard parameter should be a code reference.\n" if $guard and ref($guard) ne 'CODE';

  # declare vars
  my ($result)=('');


  # node?
  if ($item->isElementNode)
   {
    # scopy
    my @matches;

    # get item name
    my $itemName=$item->getName();


    # special cases first: whitespace
    if ($itemName eq 'text:s')
     {
      # this stands for a number of whitespaces (TODO: take care of text:c)
      return ' ';
     }
    elsif ($itemName eq 'text:line-break')
     {
      # a tab stop character (TODO: could be translated into a whitespace sequence)
      return ' ';
     }
    elsif ($itemName eq 'text:tab-stop')
     {
      # a tab stop character (TODO: could be translated into a whitespace sequence)
      return "\t";
     }
    elsif ($itemName=~/^text:table-of-content$/)
     {
      # ignore TOC's (TODO: make this configurable)
      return '';
     }

    # get paragraph style and its attributes
    my $styleName=$me->{docContent}->getStyle($item);
    my $styleObject=$me->{docContent}->getStyleElement($styleName) || $me->{docStyles}->getStyleElement($styleName);
    my %attributes=(defined $me->{docContent}->getStyle($item)) ? $me->{docContent}->getStyleAttributes($styleObject) : ();


    # special case: image
    if ($item->isImage)
     {
      # get image element
      $item=$me->{docContent}->getImageElement($item);

      # extract image data
      my (
          $imageName,
          $imageLink,
          $imageDescription
         )=(
            $me->{docContent}->imageName($item),
            $me->{docContent}->imageLink($item),
           # $me->{docContent}->imageDescription($item),
           );
                                                      

      # export internal graphics
      if ($imageLink=~m{^(\#)?Pictures/})
       {
        # make a buffer directory, if necessary (TODO: make path configurable)
        my $bufferDir='oo2ppImageBuffer';
        mkdir($bufferDir) unless -d $bufferDir;

        # export image and adapt source link
        $me->{docContent}->exportImage($item, $imageLink=join('/', $bufferDir, basename($imageLink)));
       }
      # import external graphics
      elsif ($imageLink=~m{^https?://})
       {
        # coming soon, hopefully
        return qq(.\\I<CONVERTER NOTE:> Image $imageName not importable from $imageLink yet.);
       }

      # build a tag and return it (TODDO: generalize)
      return qq(\\IMAGE{alt="$imageName" src="$imageLink"});
     }

    # we need buffers
    my ($prefixPart, $contentPart, $suffixPart);

    # open new tags
    foreach my $style (@styles)
     {
      # translate formatting into tags if possible
      if (
              exists $attributes{$style->[1]}{$style->[2]}
          and (
                  # string match?
                  (not ref($style->[3]) and $attributes{$style->[1]}{$style->[2]} eq $style->[3])
               # pattern match?
               or (ref($style->[3]) and (@matches=$attributes{$style->[1]}{$style->[2]}=~/$style->[3]/))
              )
         )
        {
         # anything to do?
         next unless ++$style->[4]==1;

         # get prefix string
         my $prefix=$style->[5];

         # replace placeholders, if necessary
         if (ref($style->[3]))
          {
           # replace last match results
           $prefix=~s/\$(\d+)/$matches[$1-1]/g;
          }

         # add prefix
         $prefixPart=join('', defined $prefixPart ? $prefixPart : '', $prefix);
        }
     }

    # recursive call
    $contentPart.=$me->traverseElement($_, $guard) foreach $item->getChildNodes;

    # close tags that were opened on this level
    foreach my $style (reverse @styles)
     {
      # translate formatting into tags if possible
      if (
              exists $attributes{$style->[1]}{$style->[2]}
          and (
                  # string match?
                  (not ref($style->[3]) and $attributes{$style->[1]}{$style->[2]} eq $style->[3])
               # pattern match?
               or (ref($style->[3]) and $attributes{$style->[1]}{$style->[2]}=~/$style->[3]/)
              )
         )
        {
         # anything to do?
         next if --$style->[4];

         # get suffix string
         my $suffix=$style->[6];

         # replace placeholders, if necessary
         if (ref($style->[3]))
          {
           # save last match results
           $suffix=~s/\$(\d+)/$matches[$1-1]/g;
          }

         # add prefix
         $suffixPart=join('', defined $suffixPart ? $suffixPart : '', $suffix);
        }
     }

    # now combine the parts as necessary
    $result.=join('',
                  defined $prefixPart ? $prefixPart : '',
                  $contentPart,
                  defined $suffixPart ? $suffixPart : '',
                 ) if defined $contentPart and $contentPart;
   }
  else
   {
    # get text, guard specials, and add the result to the functions result string
    my $text=$me->{docContent}->outputTextConversion($item->getValue() || '');
    $text=$guard->($text) if $text and $guard;
    $result.=$text;
   }

  # supply result
  $result;
 }


# class method: a translator for characters that are special in the target language
sub guardSpecials
 {
  # get and check parameters
  my ($text)=@_;

  # translate
  $text=~s/([\$>\\])/\\$1/g;

  # supply modified text
  $text;
 }



# flag successfull load
1;




# = POD TRAILER SECTION =================================================================

=pod

=head1 NOTES

First of all, please note the I<alpha state> of this software. C<OpenOffice::PerlPoint>
does support just a subset of the very rich features potentially occuring in an Open Office document.
Some features should be added later, other features have no expression in PerlPoint
and therefore are ignored.

=head2 Supported features

=over 4

=item Meta data

Selected meta data are transformed into PerlPoint variables. The names of these variables
are fix in the current version of C<OpenOffice::PerlPoint>, but shall become configurable
in later versions.

=over 4

=item Title

Stored in C<$docTitle.>

=item Subject

Stored in C<$docSubtitle.>

=item Description

Stored in C<$docDescription.>

=item Author

Stored in C<$docAuthor.>

=item Date

Stored in C<$docDate.>

=item Version

If the user defines a data named C<version>, it is stored in C<$docVersion>.

=item Copyright

If the user defines a data named C<copyright>, it is stored in C<$docCopyright>.

=back


=item Headlines

Headlines are supported. Make sure to use the predefined headline formats in the Office document,
and avoid gaps in headline hierarchies (as they will cause PerlPoint translation errors later).


=item Text formatting

Bold, italic, underlined, colorized text portions within a paragraph are translated into
the related PerlPoint tags C<\B>, C<\I>, C<\U> and C<\F>.

=item Text marked as code

In Perlpoint, text within a paragraph can be marked as "code" by the C<\C> tag. As there
is no comparable feature in OpenOffice (I know of), all text assigned to the font I<Courier New>
is treated as such code.

The font is fix for now, but shall be configurable in a future version.

=item Blocks

In PerlPoint, examples can be written into "code blocks", which are paragraphs marked by
indentation. Open Office as an office suite is not focussed on code, so again there is a
convention. All paragraphs assigned to a style "Code" are treated as blocks.

The style name is fixed for now, but shall be configurable in a future version.


=item Lists

Lists are basically supported.

Unfortunately, it is difficult to distinguish between ordered and bullet lists in OASIS OpenDocument.
That's why ordered lists are transformed into bullet lists if an OpenDocument source is translated.
For OpenOffice 1.0 documents ordered lists are handled correctly.


=item Tables

Tables are supported as long as they are not nested.


=item Images

Images I<embedded into the document> are fully supported.

I<External> images are currently translated into a text paragraph saying

  .\I<CONVERTER NOTE:> Image <image name> not importable from <image link> yet.);

Future versions shall support external image links.


=item Comments

Comments are supported.


=back


=head2 Limitations

=over 4

=item Limited to text documents

The current version can handle text documents I<only>. Spreadsheets, presentations etc. cannot
be transformed at this time.


=item Footnote support

... is invalid yet. Current results will not pass a PerlPoint converter.

=back


=head2 TOCs

Office document tables of contents cannot easily be transformed into PerlPoint TOCs. That's why
they are ignored.


=head2 POD

It should be possible to adapt this library for POD output. This might be done in the future.
Both versions could use a common base library.


=head1 Credits

This module is based on C<OpenOffice::OODoc>. Thanks to its author
Jean-Marie Gouarné for the module and his helpful support with many questions.


=head1 TODO

=over 4

=item *

Make document variable names configurable.

=item *

Make certain steps like meta data conversion optional.

=item *

Support nested tables.

=item *

TOC ignoration could become configurable.

=item *

Make name of image buffer subdirectory configurable.
Allow to use an existing, central directory.

=item *

Support other formats like spreadsheets and presentations.

=back


=head1 SEE ALSO

=over 4

=item B<OpenOffice::OODoc>

The module that made it possible to write C<OpenOffice::PerlPoint> relatively quickly.

=item B<Bundle::PerlPoint>

A bundle of packages to deal with PerlPoint documents.

=item B<oo2pp>

A OpenOffice / OpenDocument format to PerlPoint translator, distributed and installed with this module.


=back


=head1 SUPPORT

A PerlPoint mailing list is set up to discuss usage, ideas,
bugs, suggestions and translator development. To subscribe,
please send an empty message to perlpoint-subscribe@perl.org.

If you prefer, you can contact me via perl@jochen-stenzel.de
as well.


=head1 AUTHOR

Copyright (c) Jochen Stenzel (perl@jochen-stenzel.de), 2005.
All rights reserved.

Parts of the module are derived from an C<oo2pod> example script
that came with C<OpenOffice::OODoc> 1.309.

This module is free software, you can redistribute it and/or modify it
under the terms of the Artistic License distributed with Perl version
5.003 or (at your option) any later version. Please refer to the
Artistic License that came with your Perl distribution for more
details.

The Artistic License should have been included in your distribution of
Perl. It resides in the file named "Artistic" at the top-level of the
Perl source tree (where Perl was downloaded/unpacked - ask your
system administrator if you dont know where this is).  Alternatively,
the current version of the Artistic License distributed with Perl can
be viewed on-line on the World-Wide Web (WWW) from the following URL:
http://www.perl.com/perl/misc/Artistic.html


=head1 DISCLAIMER

This software is distributed in the hope that it will be useful, but
is provided "AS IS" WITHOUT WARRANTY OF ANY KIND, either expressed or
implied, INCLUDING, without limitation, the implied warranties of
MERCHANTABILITY and FITNESS FOR A PARTICULAR PURPOSE.

The ENTIRE RISK as to the quality and performance of the software
IS WITH YOU (the holder of the software).  Should the software prove
defective, YOU ASSUME THE COST OF ALL NECESSARY SERVICING, REPAIR OR
CORRECTION.

IN NO EVENT WILL ANY COPYRIGHT HOLDER OR ANY OTHER PARTY WHO MAY CREATE,
MODIFY, OR DISTRIBUTE THE SOFTWARE BE LIABLE OR RESPONSIBLE TO YOU OR TO
ANY OTHER ENTITY FOR ANY KIND OF DAMAGES (no matter how awful - not even
if they arise from known or unknown flaws in the software).

Please refer to the Artistic License that came with your Perl
distribution for more details.

