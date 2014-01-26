package App::YTDL;

use warnings;
use strict;
use 5.10.1;

our $VERSION = '0.005';


1;


__END__

=pod

=encoding UTF-8

=head1 NAME

App::YTDL - Download C<YouTube> videos.

=head1 VERSION

Version 0.005

=cut

=head1 SYNOPSIS

    yt-download -h|-?|--help

    yt-download

    yt-download url|id [url|id ...]

    yt-download -f|--file filename

Channel C<ids> are needed to prefix with C<c#>, playlist C<ids> with C<p#>.

=head1 DESCRIPTION

Download single C<YouTube> videos or/and choose videos from playlists or/and channels.

For more info see L<yt-download> or call C<yt-download -h> and choose the option I<HELP>.

=head1 REQUIREMENTS

It is required Perl version 5.10.1 or greater.

See also the requirements mentioned in L<Term::Choose> respective in L<Term::Choose::Win32>.

=head1 AUTHOR

Kuerbis <cuer2s@gmail.com>

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2013-2014 Kuerbis.

This program is free software; you can redistribute it and/or modify it under the same terms
as Perl 5.10.0.

See http://dev.perl.org/licenses/ for more information.

This program is distributed in the hope that it will be useful, but without any warranty; without even the implied
warranty of merchantability or fitness for a particular purpose.

=cut
