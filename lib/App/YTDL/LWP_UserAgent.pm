package # hide from PAUSE
App::YTDL::LWP_UserAgent;

use warnings;
use strict;
use 5.10.1;
use utf8;

use parent qw(LWP::UserAgent);

use Term::Size::Any qw(chars);

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
    local($,, $\);
    if ($status eq "begin") {
        ( my $width ) = chars( *STDERR );
        my $uri = $m->uri;
        my $len = length( $uri ) + $len_tail;
        $uri = $len > $width ? substr( $uri, -( $width - $len_tail ) ) : $uri;
        print STDERR $uri;
        $self->{progress_ani} = 0;
    }
    elsif ($status eq "end") {
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
