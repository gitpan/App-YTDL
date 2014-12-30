package # hide from PAUSE
App::YTDL::Data;

use warnings;
use strict;
use 5.010000;

use Exporter qw( import );
our @EXPORT_OK = qw( wrapper_get get_new_video_url get_download_info_as_json );

use File::Which         qw( which );
use IPC::System::Simple qw( capture );
use LWP::UserAgent      qw();
use Term::ANSIScreen    qw( :screen );
use Try::Tiny           qw( try catch );

use if $^O eq 'MSWin32', 'Win32::Console::ANSI';

sub HIDE_CURSOR () { "\e[?25l" }
sub SHOW_CURSOR () { "\e[?25h" }



sub wrapper_get {
    my ( $opt, $url ) = @_;
    my $show_progress = 1;
    my $ua = LWP::UserAgent->new( agent => $opt->{useragent}, timeout => $opt->{timeout}, show_progress => $show_progress );
    my $res;
    my $count = 1;
    RETRY: while ( 1 ) {
        my $not_ok;
        try {
            $res = $ua->get( $url );
            die $res->status_line, ': ', $url if ! $res->is_success;
        }
        catch {
            if ( $count > $opt->{retries} ) {
                return;
            }
            say "$count/$opt->{retries}  $_";
            $count++;
            $not_ok = 1;
            sleep $opt->{retries} * 2;
        };
        next RETRY if $not_ok;
        return $res;
    }
}


sub get_new_video_url {
    my ( $opt, $info, $video_id ) = @_;
    my $fmt = $info->{$video_id}{fmt};
    my $youtube_dl = which( 'youtube-dl' ) // 'youtube-dl';
    my @cmd = ( $youtube_dl );
    push @cmd, '--user-agent', $opt->{useragent} if defined $opt->{useragent};
    push @cmd, '--socket-timeout', $opt->{timeout};
    #push @cmd, '-v';
    push @cmd, '--format', $fmt, '--get-url', '--', $video_id;
    my $video_url;
    try {
        $video_url = capture( @cmd );
    }
    catch {
        say $_;
        $video_url = undef;
    };
    return $video_url;
}


sub get_download_info_as_json {
    my ( $opt, $video_id, $message ) = @_;
    my $youtube_dl = which( 'youtube-dl' ) // 'youtube-dl';
    my @cmd = ( $youtube_dl );
    push @cmd, '--user-agent', $opt->{useragent} if defined $opt->{useragent};
    push @cmd, '--socket-timeout', $opt->{timeout};
    #push @cmd, '-v';
    push @cmd, '--dump-json', '--', $video_id;
    my $json;
    my $count = 1;
    RETRY: while ( 1 ) {
        my $not_ok;
        try {
            print HIDE_CURSOR;
            print $message . '...';
            $json = capture( @cmd );
            print "\r", clline;
            print $message . "done.\n";
            print SHOW_CURSOR;
            die if ! defined $json;
        }
        catch {
            say "$count/$opt->{retries}  $video_id: $_";
            $count++;
            $not_ok = 1;
            print SHOW_CURSOR;
            sleep $opt->{retries} * 2;
        };
        if ( $count > $opt->{retries} ) {
            push @{$opt->{error_get_download_infos}}, $video_id;
            return;
        }
        next RETRY if $not_ok;
        last;
    }
    $opt->{up}++;
    return $json;
}




1;


__END__
