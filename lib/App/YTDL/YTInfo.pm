package # hide from PAUSE
App::YTDL::YTInfo;

use warnings;
use strict;
use 5.10.1;
use utf8;

use Exporter qw(import);
our @EXPORT_OK = qw(get_download_infos get_video_url);

use Encode                qw(decode_utf8);
use File::Spec::Functions qw(catfile);
use List::Util            qw(max);
use Unicode::Normalize    qw(NFC);

use List::MoreUtils    qw(any);
use Term::ANSIScreen   qw(:cursor :screen);
use Term::Size::Any    qw(chars);
use Text::LineFold;
use Try::Tiny          qw(try catch);
use Unicode::GCString;
use URI;
use URI::Escape        qw(uri_unescape);

use App::YTDL::YTConfig     qw(map_fmt_to_quality);
use App::YTDL::YTXML        qw(url_to_entry_node entry_node_to_info_hash);
use App::YTDL::GenericFunc  qw(unicode_trim encode_filename);

BEGIN {
    if ( $^O eq 'MSWin32' ) {
        require Term::Choose::Win32;
        Term::Choose::Win32::->import( 'choose' );
        require Win32::Console::ANSI;
    } else {
        require Term::Choose;
        Term::Choose::->import( 'choose' );
    }
}

use constant {
    DELETE => -1,
    APPEND => -2,
    REDO   => -3,
};


sub get_download_infos {
    my ( $opt, $info, $client ) = @_;
    my ( $cols, $rows ) = chars;
    print "\n\n\n", '=' x $cols, "\n\n", "\n" x $rows;
    print locate( 1, 1 ), cldown;
    say 'Dir  : ', $opt->{youtube_dir};
    say 'Agent: ', $client->ua->agent() || 'unknown';
    print "\n";
    my @video_ids = sort {
             $info->{$b}{type}                   cmp   $info->{$a}{type}
        ||   $info->{$a}{list_id}                cmp   $info->{$b}{list_id}
        || ( $info->{$a}{published_raw} // '0' ) cmp ( $info->{$b}{published_raw} // '0' )
        || ( $info->{$a}{title}         // ''  ) cmp ( $info->{$b}{title}         // ''  )
    } keys %$info;
    my $fmt;
    my $count = 0;
    $opt->{up} = 0;
    VIDEO:
    while ( @video_ids ) {
        my $video_id = shift @video_ids;
        my ( $print_array, $key_len, $failed );
        try {
            ( $info ) = get_print_info( $opt, $info, $client, $video_id );
            ( $info, $print_array, $key_len ) = format_print_info( $opt, $info, $video_id );
            print "\n";
            $opt->{up}++;
            print for map { NFC( $_ ) } @{$print_array};
            $opt->{up} += @{$print_array};
            print "\n";
            $opt->{up}++;
        }
        catch {
            say "$video_id - $_";
            choose( [ 'Press ENTER' ], { prompt => '' } );
            delete  $info->{$video_id};
            $failed = 1;
        };
        next VIDEO if $failed;
        my $status = $info->{$video_id}{status};
        if ( ! defined $status || $status ne 'ok' ) {
            my $prompt = $video_id . ': Status not ok - Status ' . ( $status // 'undefined' );
            choose( [ 'Press ENTER' ], { prompt => $prompt } );
            delete $info->{$video_id};
            print up( $opt->{up} ), cldown;
            $opt->{up} = 0;
            next VIDEO;
        }
        try {
            $opt->{up}++ if ! $client->{cache}{$video_id}; ###
            my $data = $client->prepare_download( $video_id );
            ( $info, $fmt ) = choose_quality( $opt, $info, $data, $client, $fmt, $video_id );
            print up( $opt->{up} ), cldown;
            $opt->{up} = 0;
            if ( $fmt < 0 ) {
                delete  $info->{$video_id}    if $fmt == DELETE;
                push    @video_ids, $video_id if $fmt == APPEND;
                unshift @video_ids, $video_id if $fmt == REDO;
            }
            else {
                $info->{$video_id}{video_url} = decode_utf8( $data->{video_url_map}{$fmt}{url} );
                $info->{$video_id}{file_name} = catfile( $opt->{youtube_dir}, get_filename( $opt, $data, $fmt ) );
                $info->{$video_id}{count}     = ++$count;
                $info->{$video_id}{fmt}       = $fmt;
                $print_array->[0] =~ s/\n\z/ ($fmt)\n/;
                unshift @$print_array, sprintf "%*.*s : %s\n", $key_len, $key_len, 'video', $count;
                print for map { NFC( $_ ) } @$print_array;
                print "\n";
            }
        }
        catch {
            say "$video_id - $_";
            choose( [ 'Press ENTER' ], { prompt => '' } );
            delete  $info->{$video_id};
        };
    }
    print "\n";
    return $info, $count;
}


sub get_print_info {
    my ( $opt, $info, $client, $video_id ) = @_;
    my $type = $info->{$video_id}{type};
    if ( ! ( $type eq 'PL' ) ) {
        my $url = URI->new( 'http://gdata.youtube.com/feeds/api/videos/' . $video_id );
        $url->query_form( 'v' => $opt->{yt_api_v} );
        my $entry = url_to_entry_node( $opt, $client, $url );
        $opt->{up}++;
        $info = entry_node_to_info_hash( $opt, $info, $entry, $type, $info->{$video_id}{list_id} );
    }
    my $info_url = URI->new( 'http://www.youtube.com/get_video_info' );
    $info_url->query_form( 'video_id' => $video_id );
    my $res = $client->ua->get( $info_url->as_string );
    die "$res->status_line: $info_url" if ! $res->is_success;
    $opt->{up}++;
    for my $item ( split /&/, $res->decoded_content ) {
        my ( $key, $value ) = split /=/, $item;
        if ( defined $value && $key =~ /^(?:title|keywords|reason|status)\z/ ) {
            $info->{$video_id}{$key} = decode_utf8( uri_unescape( $value ) );
            $info->{$video_id}{$key} =~ s/\+/ /g;
            $info->{$video_id}{$key} =~ s/(?<=\p{Word}),(?=\p{Word})/, /g if $key eq 'keywords';
        }
    }
    return $info;
}


sub format_print_info {
    my ( $opt, $info, $video_id ) = @_;
    my @keys = ( qw( title video_id author duration errorcode reason raters
                        avg_rating view_count published content description keywords ) ); #status
    for my $key ( @keys ) {
        next if ! defined $info->{$video_id}{$key};
        $info->{$video_id}{$key} =~ s/\R/ /g;
    }
    my $key_len = 13;
    my $s_tab = $key_len + length( ' : ' );
    my ( $maxcols, $maxrows ) = chars;
    $maxcols -= 2;
    my $col_max = $maxcols;
    $col_max = $col_max > $opt->{max_info_width} ? $opt->{max_info_width} : $col_max;
    my $lf = Text::LineFold->new(
        Charset       => 'utf-8',
        ColMax        => $col_max,
        Newline       => "\n",
        OutputCharset => '_UNICODE_',
        Urgent        => 'FORCE',
    );
    my $print_array;
    for my $key ( @keys ) {
        next if ! $info->{$video_id}{$key};
        $info->{$video_id}{$key} =~ s/\n+/\n/g;
        $info->{$video_id}{$key} =~ s/^\s+//;
        ( my $kk = $key ) =~ s/_/ /g;
        my $pr_key = sprintf "%*.*s : ", $key_len, $key_len, $kk;
        my $text = $lf->fold( '' , ' ' x $s_tab, $pr_key . $info->{$video_id}{$key} );
        $text =~ s/\R+\z//;
        for my $val ( split /\R+/, $text ) {
            push @$print_array, $val . "\n";
        }
    }
    if ( $opt->{auto_width} ) {
        my $ratio = @$print_array / $maxrows;
        my $begin = 0.70;
        my $end   = 1.50;
        my $step  = 0.0125;
        my $div   = ( $end - $begin ) / $step + 1;
        my $plus;
        if ( $ratio >= $begin ) {
            $ratio = $end if $ratio > $end;
            $plus = int( ( ( $maxcols - $col_max ) / $div ) * ( ( $ratio - $begin  ) / $step + 1 ) );
        }
        if ( $plus ) {
            $col_max += $plus;
            $lf->config( 'ColMax', $col_max );
            $print_array = [];
            for my $key ( @keys ) {
                next if ! $info->{$video_id}{$key};
                ( my $kk = $key ) =~ s/_/ /g;
                my $pr_key = sprintf "%*.*s : ", $key_len, $key_len, $kk;
                my $text = $lf->fold( '' , ' ' x $s_tab, $pr_key . $info->{$video_id}{$key} );
                $text =~ s/\R+\z//;
                for my $val ( split /\R+/, $text ) {
                    push @$print_array, $val . "\n";
                }
            }
        }
        if ( @$print_array > ( $maxrows - 6 ) ) {
            $col_max = $maxcols;
            $lf->config( 'ColMax', $col_max );
            $print_array = [];
            for my $key ( @keys ) {
                next if ! $info->{$video_id}{$key};
                ( my $kk = $key ) =~ s/_/ /g;
                my $pr_key = sprintf "%*.*s : ", $key_len, $key_len, $kk;
                my $text = $lf->fold( '' , ' ' x $s_tab, $pr_key . $info->{$video_id}{$key} );
                $text =~ s/\R+\z//;
                for my $val ( split /\R+/, $text ) {
                    push @$print_array, $val . "\n";
                }
            }
        }
    }
    return $info, $print_array, $key_len;
}


sub get_filename {
    my ( $opt, $data, $fmt ) = @_;
    my $title  = decode_utf8( $data->{title} );
    my $suffix = decode_utf8( $data->{suffix} );
    $suffix = 'webm' if $fmt =~ /^(?:43|44|45|46|100|101|102|103)\z/;
    $suffix = 'flv'  if $fmt =~ /^(?:5|6|34|35)\z/;
    $suffix = 'mp4'  if $fmt =~ /^(?:18|22|37|38|82|83|84|85)\z/;
    $suffix = '3gp'  if $fmt =~ /^(?:13|17|36)\z/;
    my $gcs_suff = Unicode::GCString->new( $suffix );
    my $len = $opt->{max_len_f_name} - ( $gcs_suff->columns() + length( $fmt ) + 2 );
    my $file_name = unicode_trim( $title, $len );
    $file_name = $file_name . '_' . $fmt . '.' . $suffix;
    $file_name =~ s/\s/_/g;
    $file_name =~ s/^\s+|\s+\z//g;
    $file_name =~ s/^\.+//;
    #$file_name =~ s/[^\p{Word}.()]/-/g;
    $file_name =~ s/["\/\\:*?<>|]/-/g;
    # NTFS and FAT unsupported characters: " / \\ : * ? < > |
    return NFC( $file_name );
}


sub choose_quality {
    my ( $opt, $info, $data, $client, $fmt, $video_id ) = @_;
    my @avail_fmts = map { decode_utf8( $_ ) } @{$data->{fmt_list}};
    if ( ! @avail_fmts ) {
        my $ref = map_fmt_to_quality;
        for my $fmt ( sort keys %$ref ) {
            push @avail_fmts, $fmt if $data->{video_url_map}{$fmt}{url};
        }
        if ( ! @avail_fmts ) {
            my $prompt = 'video_id ' . $video_id . ': Error in fetching available fmts.' . "\n";
            $prompt .= 'Skipping video "' . $info->{$video_id}{title} . '".';
            choose( [ 'Press Enter to continue' ], { prompt => $prompt } );
            $fmt = DELETE;
            return $info, $fmt;
        }
    }
    my $fmt_ok;
    if ( $opt->{auto_quality} == 3 ) {
        my @pref_qualities = @{$opt->{preferred}//[]};
        if ( ! @pref_qualities ) {
            print "\n";
            $opt->{up}++;
            say 'video_id: ' . $video_id . ' - no preferred qualities found!';
            $opt->{up}++;
        }
        else {
            for my $pq ( @pref_qualities ) {
                if ( any{ $pq eq $_ } @avail_fmts ) {
                    $fmt = $pq;
                    $fmt_ok = 1;
                    last;
                }
            }
            if ( ! $fmt_ok ) {
                print "\n";
                $opt->{up}++;
                say 'video_id: ' . $video_id . ' - no matches between preferred fmts and available fmts!';
                $opt->{up}++;
            }
        }
    }
    elsif ( $opt->{auto_quality} == 2 ) {
        if ( ! defined $opt->{aq} ) {
            $fmt = set_fmt( $opt, $data );
            $opt->{aq} = $fmt if $fmt >= 0;
            $fmt_ok = 1;
        }
        elsif ( any{ $_ eq $opt->{aq} } @avail_fmts ) {
            $fmt = $opt->{aq};
            $fmt_ok = 1;
        }
    }
    elsif ( $opt->{auto_quality} == 1 ) {
        if ( $info->{$video_id}{type} =~ /^[PC]L\z/ ) {
            my $aq = $info->{$video_id}{type} . '#' . $info->{$video_id}{list_id};
            if ( ! defined $opt->{$aq} ) {
                $fmt = set_fmt( $opt, $data );
                $opt->{$aq} = $fmt if $fmt >= 0;
                $fmt_ok = 1;
            }
            elsif ( any{ $_ eq $opt->{$aq} } @avail_fmts ) {
                $fmt = $opt->{$aq};
                $fmt_ok = 1;
            }
        }
    }
    if ( ! $fmt_ok ) {
        $fmt = set_fmt( $opt, $data );
    }
    if ( $fmt >= 0 && ! $data->{video_url_map}{$fmt}{url} ) {
        my $prompt = 'video_id "' . $video_id . '": fmt ' . $fmt . ' not supported.';
        choose( [ 'Press ENTER to continue' ], { prompt => $prompt } );
        $fmt = DELETE;
    }
    return $info, $fmt;
}


sub set_fmt {
    my ( $opt, $data ) = @_;
    my @avail_fmts = map { decode_utf8( $_ ) } @{$data->{fmt_list}};
    my $ref = map_fmt_to_quality();
    my $list_res;
    for my $fmt ( keys %$ref ) {
        ( my $res = $ref->{$fmt} ) =~ s/\s+/ /g;
        $res =~ s/^\s+|\s+\z//g;
        $list_res->{$fmt} = $res // decode_utf8( $data->{video_url_map}{$fmt}{resolution} ) . '_NEW';
    }
    my $len_res = max map { length } @{$list_res}{@avail_fmts};
    my $len_fmt = max map { length } @avail_fmts;
    my @choices;
    for my $fmt ( sort { $a <=> $b } @avail_fmts ) {
        push @choices, sprintf "%*d : %-*s", $len_fmt, $fmt, $len_res, $list_res->{$fmt};
    }
    print "\n";
    $opt->{up}++;
    my $fmt_res = choose(
        [ undef, @choices ],
        { prompt => 'Your choice: ', order => 0, undef => 'Menu' }
    );
    my $fmt;
    if ( ! defined $fmt_res ) {
        my ( $delete, $append, $redo ) = ( 'Delete', 'Append', 'Redo' );
        my $choice = choose(
            [ undef, $append, $delete, $redo ],
            { prompt => 'Your choice: ', undef => $opt->{quit} }
        );
        exit if ! defined $choice;
        $fmt = DELETE if $choice eq $delete;
        $fmt = APPEND if $choice eq $append;
        $fmt = REDO   if $choice eq $redo;
    }
    else {
        $fmt = ( split /\s:\s/, $fmt_res )[0];
        $fmt =~ s/^\s+|\s+\z//g;
    }
    return $fmt;
}


sub get_video_url {
    my ( $opt, $info, $client, $video_id ) = @_;
    delete $client->{cache}{$video_id};             ###
    my $data = $client->prepare_download( $video_id );
    my $video_url = decode_utf8( $data->{video_url_map}{$info->{$video_id}{fmt}}{url} );
    return $video_url;
}


1;


__END__
