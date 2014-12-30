package # hide from PAUSE
App::YTDL::Download;

use warnings;
use strict;
use 5.010000;

use Exporter qw( import );
our @EXPORT_OK = qw( download_youtube );

use Fcntl          qw( LOCK_EX SEEK_END );
use File::Basename qw( basename );
use Time::HiRes    qw( gettimeofday tv_interval );

use Encode::Locale   qw();
use LWP::UserAgent   qw();
use Term::ANSIScreen qw( :cursor :screen );
use Try::Tiny        qw( try catch );

use if $^O eq 'MSWin32', 'Win32::Console::ANSI';

use App::YTDL::Data   qw( get_new_video_url );
use App::YTDL::Helper qw( sec_to_time insert_sep encode_fs encode_stdout );

use constant {
    HIDE_CURSOR => "\e[?25l",
    SHOW_CURSOR => "\e[?25h",
};

END { print SHOW_CURSOR }


sub download_youtube {
    my ( $opt, $info ) = @_;
    my $ua = LWP::UserAgent->new( agent => $opt->{useragent}, show_progress => 0 );
    for my $video_id ( sort { $info->{$a}{count} <=> $info->{$b}{count} } keys %$info ) {
        try {
            my $file_name_OS = encode_fs( $info->{$video_id}{file_name} );
            unlink $file_name_OS or die $! if -f $file_name_OS && $opt->{overwrite};
            _download_video( $opt, $info, $ua, $video_id );
        }
        catch {
            say "$video_id - $_";
        }
    }
    return;
}


sub _download_video {
    my ( $opt, $info, $ua, $video_id ) = @_;
    my $nr            = $info->{$video_id}{count};
    my $video_url     = $info->{$video_id}{video_url};
    my $file_name     = $info->{$video_id}{file_name};
    my $file_name_OS  = encode_fs( $file_name );
    my $file_basename = basename $file_name;
    print HIDE_CURSOR;
    say '  -----' if $nr > 1;
    binmode STDOUT, ':pop';
    printf "  %s (%s)\n", encode_stdout( $file_basename ), $info->{$video_id}{duration} // '?';
    binmode STDOUT, ':encoding(console_out)';
    my $tvl = length $opt->{total_nr_videos};
    my $video_count = sprintf "%${tvl}s from %s", $nr, $opt->{total_nr_videos};
    my $length_video_count = length $video_count;
    local $SIG{INT} = sub {
        print cldown, "\n";
        print SHOW_CURSOR;
        exit( 1 );
    };
    my $p = {};
    my $try = 1;
    RETRY: while ( 1 ) {
        $p->{size}      = -s $file_name_OS // 0;
        $p->{starttime} = gettimeofday;
        my $retries = '    ';
        if ( $try > 1 ) {
            $retries = "$try/$opt->{retries}";
            $video_count = ' ' x $length_video_count;
        }
        my $at = '';
        my $res;
        if ( ! $p->{size} ) {
            open my $fh, '>:raw', $file_name_OS or die $!;
            printf _p_fmt( $opt, "start" ), $video_count, $retries, $at;
            _log_info( $opt, $info, $video_id ) if $opt->{log_info};
            $res = $ua->get(
                $video_url,
                ':content_cb' => _return_callback( $opt, $fh, $p ),
            );
            close $fh or die $!;
        }
        elsif ( $p->{size} ) {
            $at = sprintf "@%.2fM", $p->{size} / 1024 ** 2; #
            open my $fh, '>>:raw', $file_name_OS or die $!;
            printf _p_fmt( $opt, "start" ), $video_count, $retries, $at;
            $res = $ua->get(
                $video_url,
                'Range'       => "bytes=$p->{size}-",
                ':content_cb' => _return_callback( $opt, $fh, $p ),
            );
            close $fh or die $!;
        }
        print up;
        print cldown;
        my $status = $res->code;
        my $pr_status = 'status ' . $status;
        my $dl_time = sec_to_time( int( tv_interval( [ $p->{starttime} ] ) ), 1 );
        my $avg_speed = '';
        my $size = '';
        my $incomplete = '';
        if ( $status =~ /^(200|206|416)/ ) {
            my $file_size = -s $file_name_OS // -1;
            if ( $p->{total} ) {
                if ( $file_size != $p->{total} ) {
                    $retries = "$try/$opt->{retries}";
                    my $pr_total = insert_sep( $p->{total} );
                    my $l = length( $pr_total );
                    $size = sprintf "%7.2fM", $file_size / 1024 ** 2;
                    $incomplete = sprintf " Incomplete: %${l}s/%s ", insert_sep( $file_size ), $pr_total;
                }
                elsif ( $status =~ /^20[06]\z/ ) {
                    $size = sprintf "%7.2fM", $p->{total} / 1024 ** 2;
                }
                $avg_speed = sprintf "avg %sk/s", $p->{kbs_avg} || '--';
            }
            $pr_status = '' if $status == 200;
            if ( $status == 416 ) {
                $dl_time = '';
                $at = sprintf "%.2fM", $p->{size} / 1024 ** 2;
                printf _p_fmt( $opt, "status_416" ), $video_count, $retries, $dl_time, $at, $pr_status;
            }
            else {
                printf _p_fmt( $opt, "status" ), $video_count, $retries, $dl_time, $size, $avg_speed, $at, $pr_status, $incomplete;
            }
            last RETRY if $p->{total} && $p->{total} == $file_size;
            last RETRY if $status == 416;
        }
        else {
            $retries = "$try/$opt->{retries}";
            $pr_status = 'status ' . $status . '  Fetching new video url ...';
            my $new_video_url = get_new_video_url( $opt, $info, $video_id );
            if ( ! $new_video_url ) {
                $pr_status .=  ' failed!';
            }
            elsif ( $new_video_url eq $video_url ) {
                $pr_status .= $res->status_line;
            }
            else {
                $video_url = $new_video_url;
            }
            printf _p_fmt( $opt, "status" ), $video_count, $retries, $dl_time, $size, $avg_speed, $at, $pr_status, $incomplete;
        }
        $try++;
        if ( $try > $opt->{retries} ) {
            push @{$opt->{incomplete_download}}, $video_url;
            last RETRY;
        }
        sleep 4 * $try;
    }
    print SHOW_CURSOR;
    return;
}


sub _log_info {
    my ( $opt, $info, $video_id ) = @_;
    my ( $sec, $min, $hour, $mday, $mon, $year ) = localtime;
    my $log_str = sprintf( "%04d-%02d-%02d %02d:%02d", $year + 1900, $mon + 1, $mday, $hour, $min )
        . '>  ' . sprintf( "%11s", $info->{$video_id}{youtube} ? $video_id : ( $info->{$video_id}{extractor_key} // '' ) . ' ' . ( $info->{$video_id}{id} // '' ) )
        . ' | ' . ( $info->{$video_id}{uploader_id} // '------' )
        . ' | ' . ( $info->{$video_id}{playlist_id} // '----------' )
        . ' | ' . ( $info->{$video_id}{upload_date} // '0000-00-00' )
        . '   ' . basename( $info->{$video_id}{file_name} );
    open my $log, '>>:encoding(UTF-8)', encode_fs( $opt->{log_file} ) or die $!;
    flock $log, LOCK_EX     or die $!;
    seek  $log, 0, SEEK_END or die $!;
    say   $log $log_str;
    close $log or die $!;
}


sub _p_fmt {
    my ( $opt, $key ) = @_;
    my %hash = (
        start        => "  %s  %3s  %9s\n", ###
        status_416   => "  %s  %3s  %7s  %9s   %s\n",
        status       => "  %s  %3s  %7s  %9s  %11s   %s    %s  %s\n",
        info_row1    => "%9.*f %s %37s %"    . (      $opt->{kb_sec_len} ) . "sk/s\n",
        info_row2    => "%9.*f %s %6.*f%% %" . ( 30 + $opt->{kb_sec_len} ) . "sk/s\n",
        info_nt_row1 => " %34s %24sk/s\n",
        info_nt_row2 => "%9.*f %s %48sk/s\n",
    );
    return $hash{$key};
}


sub _return_callback {
    my ( $opt, $fh, $p ) = @_;
    my $time = $p->{starttime};
    my ( $inter, $kbs, $chunk_size, $download, $eta ) = ( 0 ) x 5;
    my $resume_size = $p->{size} // 0;
    return sub {
        my ( $chunk, $res, $proto ) = @_;
        $inter += tv_interval( [ $time ] );
        print $fh $chunk;
        my $received = tell $fh;
        $chunk_size += length $chunk;
        $download = $received - $resume_size;
        $p->{total} = $res->header( 'Content-Length' ) // 0;
        if ( $download > 0 && $inter > 2 ) {
            $p->{kbs_avg} = ( $download / 1024 ) / tv_interval[ $p->{starttime} ];
            $eta = sec_to_time( int( ( $p->{total} - $download ) / ( $p->{kbs_avg} * 1024 ) ), 1 );
            $p->{kbs_avg} = int( $p->{kbs_avg} );
            $eta = undef if ! $p->{kbs_avg};
            $kbs = int( ( $chunk_size / 1024 ) / $inter );
            $inter = 0;
            $chunk_size = 0;
        }
        my ( $info1, $info2 );
        my $exp = { 'M' => 2, 'G' => 3 };
        if ( $p->{total} ) {
            $p->{total} += $resume_size if $resume_size;
            my $thresh = 100_000_000 * 2 ** ( $opt->{kb_sec_len} - 2 );
            my $percent = ( $received / $p->{total} ) * 100;
            my $unit = length $p->{total} <= 10 ? 'M' : 'G';
            my $prec = 2;
            $info1 = sprintf _p_fmt( $opt, "info_row1" ),
                                $prec, $p->{total} / 1024 ** $exp->{$unit}, $unit,
                                'ETA ' . ( $eta || '-:--:--' ),
                                $p->{kbs_avg} || '--',
            $info2 = sprintf _p_fmt( $opt, "info_row2" ),
                                $prec, $received / 1024 ** $exp->{$unit}, $unit,
                                $p->{total} > $thresh ? 2 : 1, $percent,
                                $kbs || '--';
        }
        else {
            my $unit = length $received <= 10 ? 'M' : 'G';
            my $prec = 2;
            $info1 = sprintf _p_fmt( $opt, "info_nt_row1" ), 'Could not fetch total file-size!', $p->{kbs_avg} || '--';
            $info2 = sprintf _p_fmt( $opt, "info_nt_row2" ), $prec, $received / 1024 ** $exp->{$unit}, $unit, $kbs || '--';
        }
        print "\r", clline, $info1;
        print "\r", clline, $info2;
        print "\n", up( 3 );
        $time = gettimeofday;
    };
}




1;


__END__
