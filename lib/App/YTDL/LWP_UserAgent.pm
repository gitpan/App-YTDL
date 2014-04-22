package # hide from PAUSE
App::YTDL::LWP_UserAgent;

use warnings;
use strict;
use 5.010001;

use parent qw( LWP::UserAgent );

use if $^O eq 'MSWin32', 'Win32::Console::ANSI';

use App::YTDL::GenericFunc qw( term_size );

use constant {
    HIDE_CURSOR => "\e[?25l",
    SHOW_CURSOR => "\e[?25h",
};

my @ANI = qw(- \ | /);

sub progress {
    my( $self, $status, $m ) = @_;
    return unless $self->{show_progress};

    my $len_tail = length '.[.]';
    print STDERR HIDE_CURSOR;
    local( $,, $\ );
    if ( $status eq "begin" ) {
        ( my $width ) = term_size( *STDERR );
        my $uri = $m->uri;
        my $len = length( $uri ) + $len_tail;
        $uri = $len > $width ? substr( $uri, -( $width - $len_tail ) ) : $uri;
        print STDERR $uri;
        $self->{progress_ani} = 0;
    }
    elsif ( $status eq "end" ) {
        delete $self->{progress_ani};
        print STDERR ' ' x $len_tail, "\n";
    }
    else {
        print STDERR ' [', $ANI[$self->{progress_ani}++], ']', "\b" x $len_tail;
        $self->{progress_ani} %= @ANI;
    }
    #print STDERR SHOW_CURSOR;
    STDERR->flush;
}


1;


__END__
