package # hide from PAUSE
App::YTDL::YTDownload;

use warnings;
use strict;
use 5.10.1;
use utf8;

use Exporter qw(import);
our @EXPORT_OK = qw(download_youtube);

use Fcntl          qw(LOCK_EX SEEK_END);
use File::Basename qw(basename);
use Time::HiRes    qw(gettimeofday tv_interval);

use Term::ANSIScreen qw(:cursor :screen);
use Try::Tiny        qw(try catch);

use App::YTDL::YTInfo       qw(get_download_infos get_video_url);
use App::YTDL::GenericFunc  qw(sec_to_time insert_sep encode_filename);

BEGIN {
    if ( $^O eq 'MSWin32' ) {
        require Win32::Console::ANSI;
    }
}

use constant {
    HIDE_CURSOR => "\e[?25l",
    SHOW_CURSOR => "\e[?25h",
};

END { print SHOW_CURSOR }


sub download_youtube {
    my ( $opt, $info, $client ) = @_;
    ( $info, my $total_nr ) = get_download_infos( $opt, $info, $client );
    return if $total_nr == 0;
    for my $video_id ( sort { $info->{$a}{count} <=> $info->{$b}{count} } keys %$info ) {
        try {
            my $file_name_OS = encode_filename( $info->{$video_id}{file_name} );
            unlink $file_name_OS or die $! if -f $file_name_OS && $opt->{overwrite};
            $client->ua->show_progress( 0 );
            download_video( $opt, $info, $client, $total_nr, $video_id );
            $client->ua->show_progress( 1 );
        }
        catch {
            say "$video_id - $_";
        }
    }
}


sub download_video {
    my ( $opt, $info, $client, $total_nr, $video_id ) = @_;
    my $file_name_OS  = encode_filename( $info->{$video_id}{file_name} );
    my $nr            = $info->{$video_id}{count};
    my $video_url     = $info->{$video_id}{video_url};
    my $file_basename = basename $info->{$video_id}{file_name};
    print HIDE_CURSOR;
    say '  -----' if $nr > 1;
    printf "  %s (%s)\n", $file_basename, $info->{$video_id}{duration};
    local $SIG{INT} = sub {
        print cldown, "\n";
        print SHOW_CURSOR;
        exit( 1 );
    };
    my $p = {};
    TRY: for my $try ( 1 .. $opt->{retries} ) {
        $p->{size}      = -s $file_name_OS // 0;
        $p->{starttime} = gettimeofday;
        my $retries     = "$try/$opt->{retries}";
        my $video_count = "$nr from $total_nr";
        my $res;
        if ( ! $p->{size} ) {
            open my $fh, '>:raw', $file_name_OS or die $!;
            printf p_fmt( $opt, 'start' ), $video_count, $retries, '';
            log_info( $opt, $info, $video_id ) if $opt->{log_info};
            $res = $client->ua->get(
                $video_url,
                ':content_cb' => return_callback( $opt, $fh, $p ),
            );
            close $fh or die $!;
        }
        elsif ( $p->{size} ) {
            open my $fh, '>>:raw', $file_name_OS or die $!;
            printf p_fmt( $opt, 'start' ), $video_count, $retries, sprintf "@ %.2f M", $p->{size} / 1024 ** 2;
            $res = $client->ua->get(
                $video_url,
                'Range'       => "bytes=$p->{size}-",
                ':content_cb' => return_callback( $opt, $fh, $p ),
            );
            close $fh or die $!;
        }
        print cldown;
        my $status = $res->code;
        my $dl_time = sec_to_time( int( tv_interval( [ $p->{starttime} ] ) ), 1 );
        if ( $status =~ /^(200|206|416)/ ) {
            my $part2 = '';
            my $file_size = -s $file_name_OS // -1;
            if ( $p->{total} ) {
                if ( $file_size != $p->{total} ) {
                    $part2 .= sprintf " Incomplete: %s/%s ", insert_sep( $file_size ), insert_sep( $p->{total} );
                    $part2 .= sprintf "   avg %2sk/s", $p->{kbs_avg} if $p->{kbs_avg};
                }
                elsif ( $status =~ /^20[06]\z/ ) {
                    $part2 .= sprintf " %7.2f M   avg %2sk/s", $p->{total} / 1024 ** 2, $p->{kbs_avg};
                }
            }
            printf p_fmt( $opt, 'status' ), $dl_time, $status, $part2;
            last TRY if $p->{total} && $p->{total} == $file_size;
            last TRY if $status == 416;
        }
        else {
            printf p_fmt( $opt, 'status' ), $dl_time, $status, 'Trying to get a new video url ...';
            my $new_video_url = get_video_url( $opt, $info, $client, $video_id );
            if ( ! $new_video_url ) {
                die 'Fetching new video url: failed!';
            }
            if ( $new_video_url eq $video_url ) {
                die $res->status_line, ' : ', $video_url;
            }
            else {
                $video_url = $new_video_url;
            }
        }
        sleep 5 * $try;
    }
    print SHOW_CURSOR;
    return;
}


sub log_info {
    my ( $opt, $info, $video_id ) = @_;
    my ( $sec, $min, $hour, $mday, $mon, $year ) = localtime;
    my $log_str = sprintf( "%04d-%02d-%02d %02d:%02d", $year + 1900, $mon + 1, $mday, $hour, $min )
        . '>  ' . $video_id
        . ' | ' . ( $info->{$video_id}{channel_id} // '------' )
        . ' | ' . ( $info->{$video_id}{type} eq 'PL' ? $info->{$video_id}{list_id} : '----------' )
        . ' | ' . ( $info->{$video_id}{published} // '0000-00-00' )
        . '   ' . basename( $info->{$video_id}{file_name}
    );
    open my $log, '>>:encoding(UTF-8)', encode_filename( $opt->{log_file} ) or die $!;
    flock $log, LOCK_EX     or die $!;
    seek  $log, 0, SEEK_END or die $!;
    say   $log $log_str;
    close $log or die $!;
}


sub p_fmt {
    my ( $opt, $key ) = @_;
    my %hash = (
        start        => "  %s   %s   %s\n",
        status       => "  %s  status %s  %s\n",
        info_row1    => "%9.*f %s %37s %"    . (      $opt->{kb_sec_len} ) . "sk/s\n",
        info_row2    => "%9.*f %s %6.*f%% %" . ( 30 + $opt->{kb_sec_len} ) . "sk/s\n",
        info_nt_row1 => " %34s %24sk/s\n",
        info_nt_row2 => "%9.*f %s %48sk/s\n",
    );
    return $hash{$key};
}


sub return_callback {
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
            $eta = sec_to_time( int( ( $p->{total} - $download ) / ( $p->{kbs_avg} * 1024 ) ) );
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
            $info1 = sprintf p_fmt( $opt, 'info_row1' ),
                                $prec, $p->{total} / 1024 ** $exp->{$unit}, $unit,
                                'ETA ' . ( $eta || '-:--:--' ),
                                $p->{kbs_avg} || '--',
            $info2 = sprintf p_fmt( $opt, 'info_row2' ),
                                $prec, $received / 1024 ** $exp->{$unit}, $unit,
                                $p->{total} > $thresh ? 2 : 1, $percent,
                                $kbs || '--';
        }
        else {
            my $unit = length $received <= 10 ? 'M' : 'G';
            my $prec = 2;
            $info1 = sprintf p_fmt( $opt, 'info_nt_row1' ), 'Could not fetch total file-size!', $p->{kbs_avg} || '--';
            $info2 = sprintf p_fmt( $opt, 'info_nt_row2' ), $prec, $received / 1024 ** $exp->{$unit}, $unit, $kbs || '--';
        }
        print "\r", clline, $info1;
        print "\r", clline, $info2;
        print "\n", up( 3 );
        $time = gettimeofday;
    };
}




1;


__END__
