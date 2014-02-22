package App::YTDL;

use warnings;
use strict;
use 5.10.1;

our $VERSION = '0.010';


1;


__END__

=pod

=encoding UTF-8

=head1 NAME

App::YTDL - Download YouTube videos.

=head1 VERSION

Version 0.010

=cut

=head1 SYNOPSIS

    yt-download -h|-?|--help

    yt-download

    yt-download url|id [url|id ...]

    yt-download -f|--file filename

Channel ids need a C<c#> prefix, playlist ids a C<p#> prefix.

=head1 DESCRIPTION

Download single YouTube videos or/and choose videos from playlists or/and channels.

For more info see L<yt-download> or call C<yt-download -h> and choose the option HELP.

=head1 REQUIREMENTS

It is required Perl version 5.10.1 or greater.

See also the requirements mentioned in L<Term::Choose> or in L<Term::Choose::Win32> if OS is MSWin32.

=head1 AUTHOR

Kuerbis <cuer2s@gmail.com>

=head1 CREDITS

Essential parts of this application are using methods of the L<WWW::YouTube::Download> module.

Thanks to the L<Perl-Community.de|http://www.perl-community.de> and the people form
L<stackoverflow|http://stackoverflow.com> for the help.

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2013-2014 Kuerbis.

This program is free software; you can redistribute it and/or modify it under the same terms as Perl 5.10.0.
For details, see the full text of the licenses in the file LICENSE.

=cut
