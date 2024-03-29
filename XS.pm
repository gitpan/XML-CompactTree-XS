package XML::CompactTree::XS;

use warnings;
use strict;
use XML::LibXML;

=head1 NAME

XML::CompactTree::XS - a fast builder of compact tree structures from XML documents

=head1 VERSION

Version 0.02

=cut


our $VERSION = '0.02';

use base qw(Exporter);
use vars qw( @EXPORT @EXPORT_OK %EXPORT_TAGS );

use constant do {
  my @flags = (qw(
		   XCT_IGNORE_WS
		   XCT_IGNORE_SIGNIFICANT_WS
		   XCT_IGNORE_PROCESSING_INSTRUCTIONS
		   XCT_IGNORE_COMMENTS
		   XCT_USE_QNAMES
		   XCT_KEEP_NS_DECLS
		   XCT_TEXT_AS_STRING
		   XCT_ATTRIBUTE_ARRAY
		   XCT_PRESERVE_PARENT
		   XCT_MERGE_TEXT_NODES
		   XCT_LINE_NUMBERS
		   XCT_DOCUMENT_ROOT
		));
  $EXPORT_TAGS{flags} = \@flags;
  my %c = map { ($flags[$_] => (1 << $_)) }  0..$#flags;
  \%c
};

BEGIN {
  @EXPORT    = (map @$_, values %EXPORT_TAGS);
  @EXPORT_OK = @EXPORT;
  $EXPORT_TAGS{all}=\@EXPORT_OK;
}



require XSLoader;
XSLoader::load('XML::CompactTree::XS', $VERSION);

=head1 SYNOPSIS

    use XML::CompactTree::XS;
    use XML::LibXML::Reader;

    my $reader = XML::LibXML::Reader->new(location => $url);
    ...
    my $tree = XML::CompactTree::XS::readSubtreeToPerl($reader,
                 XCT_DOCUMENT_ROOT|XCT_IGNORE_WS|XCT_IGNORE_COMMENTS);
    ...

=head1 DESCRIPTION

This module provides functions that use XML::LibXML::Reader to parse
an XML document into a parse tree formed of nested arrays (and hashes). It
aims to be very fast in doing that and to presreve all relevant
information from the XML (including namespaces, document order, mixed
content, etc.). It sacrifices user friendliness for speed.

=head1 PURPOSE

I wrote this module because I noticed that repeated calls to methods
implemented in C (XS) were very expensive in Perl.

Therefore traversing a large DOM tree using XML::LibXML or iterating
over an XML stream using XML::LibXML::Reader was much slower than
traversing similarly large and structured native Perl data
structures.

This module allows the user to do just one call XS within which a
document parse tree built using native Perl data structures (arrays
and optionally hashes). It does not provide full DOM navigation but
attempts to provide maximum amount of information.  Its memory
footprint should be somewhat smaller than that of a corresponding
XML::LibXML DOM tree.

=head1 EXPORT

By default, the following constants are exported (C<:flags> export
tag) to be used as flags for the tree builder:

   XCT_IGNORE_WS
   XCT_IGNORE_SIGNIFICANT_WS
   XCT_IGNORE_PROCESSING_INSTRUCTIONS
   XCT_IGNORE_COMMENTS
   XCT_USE_QNAMES           /* not yet implemented */
   XCT_KEEP_NS_DECLS
   XCT_TEXT_AS_STRING       /* not yet implemented */
   XCT_ATTRIBUTE_ARRAY
   XCT_PRESERVE_PARENT      /* not yet implemented */
   XCT_MERGE_TEXT_NODES     /* not yet implemented */
   XCT_DOCUMENT_ROOT

=head1 FUNCTIONS

=head2 readSubtreeToPerl( $reader, $flags, \my %ns )

Uses a given XML::LibXML::Reader parser objects to parse a subtree at
the current reader position to build a tree formed of nested arrays
(see L<OUTPUT FORMAT>).

=over 4

=item reader

A XML::LibXML::Reader object to use as the reader. While building the
tree, the reader moves to the next node on the current or higher
level.

=item flags

An integer consisting of 1 bit flags (see constants in the EXPORT section).
Use binary or (|) to combine individual flags.

The following flags are NOT implemented yet:

   XCT_USE_QNAMES, XCT_TEXT_AS_STRING, XCT_PRESERVE_PARENT, XCT_MERGE_TEXT_NODES


=item ns

You may pass an empty hash reference that will be populated by a
namespace_uri to namespace_index map, that can be used to decode
namespace indexes in the resulting data structure (see L<OUTPUT
FORMAT>).

=back

=cut

sub readSubtreeToPerl {
  my ($reader,$flags,$ns)=@_;
  $ns||={};
  $ns->{''}=0;
  my $ret = _readSubtreeToPerl($reader,$flags,$ns,1,0);
  return $ret->[0];
}

=head2 readLevelToPerl( $reader, $flags, $ns )

Like C<readSubtreeToPerl>, but reads the subtree
at the current reader position and all its following siblings.
It returns an array reference of representations of these subtrees
as in the format described in L<OUTPUT FORMAT>.

=cut

sub readLevelToPerl {
  my ($reader,$flags,$ns)=@_;
  $ns||={};
  $ns->{''}=0;
  my $ret = _readSubtreeToPerl($reader,$flags,$ns,1,1);
  return $ret;
}

=head1 OUTPUT FORMAT

The result of parsing a subtree is a Perl array reference C<$node>
contains a node type followed by node data whose interpretation on
further positions in $node depends on the node type, as described
below:

=head2 Any Node

=over 5

=item *

$node->[0] is an integer representing the node type. Use
XML::LibXML::Reader node-tye constants, e.g. XML_READER_TYPE_ELEMENT
for an element node, XML_READER_TYPE_TEXT for text node, etc.

=back

=head2 Document or Document Fragment Nodes

=over 5

=item *

$node->[1] contains the document encoding

=item *

$node->[2] is an array reference containing similar represention of
all the child nodes of the document (fragment).

=back 

Note: XML::LibXML::Reader does not document node by default, which
means that calling readSubtreeToPerl on a reader object in its initial
state only parses the first node in the document (which can be the
root element, but also a comment or a processing instruction). Use
XCT_DOCUMENT_ROOT flag to force creating a document node in such case.

=head2  Element nodes

=over 5

=item *

$node->[1] is the local name (UTF-8 encoded character string)

=item *

$node->[2] is the namespace index (see L<NAMESPACES> below)

=item *

$node->[3] is undef if the element has no attributes. Otherwise if
XCT_ATTRIBUTE_ARRAY flag was used, $node->[3] is an array reference of
the form C<[ name1, value1, name2, value2, ....]> of attribute names and
corresponding values. If XCT_ATTRIBUTE_ARRAY flag was not used, then
$node->[3] is a hash reference mapping attribute names to the
corresponding attribute values C<{ name1=>value1, name2=>value2...}>

The flag XCT_KEEP_NS_DECLS controls whether namespace declarations
(xmlns=... or xmlns:prefix=...) are included along with normal
attributes or not.

Note: there is no support for namespaced attributes yet, but the
attribute names are stored as QNames, so one can always use
XCT_KEEP_NS_DECLS to keep track of namespace prefix declarations and
do the resolving manually. Support for namespaced attributes is
planned.

=item *

If XTC_LINE_NUMBERS flag was used, $node->[4] contains the line number
of the element and $node->[5] contains an array reference containing
similar representions of the child nodes of the current node.

=item *

If XTC_LINE_NUMBERS flag was NOT used, $node->[4] contains an array
reference of similar representations of the child nodes of the current
node.

=back

=head2 Text, CDATA, Comment and White-Space Nodes

=over 5

=item *

$node->[1] contains the node value (UTF-8 encoded character string)

=back

=head2 Unparsed Entity, Processing-Instruction, and Notation Nodes

=over 5

=item *

$node->[1] contains the local name (there is no support for
namespaces on these types of nodes yet)

=item *

$node->[2] contains the node value

=back

=head2 Skipping Less-Significant Nodes

White-space (non-significant or significant), processing-instruction
and comment nodes can be completely skipped, using the following
flags:

   XCT_IGNORE_WS
   XCT_IGNORE_SIGNIFICANT_WS
   XCT_IGNORE_PROCESSING_INSTRUCTIONS
   XCT_IGNORE_COMMENTS

=head1 NAMESPACES

Namespaces of element nodes are stored in the element node as an
integer. 0 always represents nodes without namespace, all other
namespaces are assigned unique numbers in an increasing order as they
appear. You can pass an empty hash reference to the parsing functions
to obtain the mapping.

=head2 Example

  use XML::CompactTree::XS;
  use XML::LibXML::Reader;

  my $reader = XML::LibXML::Reader->new(location => $ARGV[0]);
  my %ns;
  my $data = XML::CompactTree::XS::readSubtreeToPerl( $reader, XCT_DOCUMENT_ROOT, \%ns );
  $ns_map[$ns{$_}]=$_ for keys %ns;
  my @nodes = ($data);
  while (@nodes) {
    my $node = shift @nodes;
    my $type = $node->[0];
    if ($type == XML_READER_TYPE_ELEMENT) {
      print "element $node->[1] is from ns $node->[2] '$ns_map[$node->[2]]'\n";
      push @nodes, @{$node->[4]}; # queue children
    } elsif ($type == XML_READER_TYPE_DOCUMENT) {
      push @nodes, @{$node->[2]}; # queue children
    }
  }

=head1 PLANNED FEATURES

Planned flags:

   XCT_USE_QNAMES - use QNames instead of local names for all nodes
   XCT_TEXT_AS_STRING - put text nodes into the tree as plain scalars
   XCT_PRESERVE_PARENT - add a slot with a weak reference to the parent node
   XCT_MERGE_TEXT_NODES - merge adjacent text/cdata nodes together

Features: allow blessing the array refs to default or user-specified
classes; the default classes would provide a very small subset of DOM
methods to retrieve node information, manipulate the tree, and
possibly serialize the parse tree back to XML.

=head1 AUTHOR

Petr Pajas, C<< <pajas@matfyz.cz> >>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-xml-compacttree-xs@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=XML-CompactTree-XS>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 COPYRIGHT & LICENSE

Copyright 2008-2009 Petr Pajas, All Rights Reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=head1 SEE ALSO

  XML::LibXML::Reader

=cut

1; # End of XML::CompactTree::XS
