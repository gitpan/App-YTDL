package # hide from PAUSE
App::YTDL::YTInfo;

use warnings;
use strict;
use 5.010000;

use Exporter qw( import );
our @EXPORT_OK = qw( get_download_infos );

use Encode                qw( decode_utf8 );
use File::Spec::Functions qw( catfile );
use List::Util            qw( max );

use List::MoreUtils   qw( any );
use LWP::UserAgent    qw();
use Term::ANSIScreen  qw( :cursor :screen );
use Term::Choose      qw( choose );
use Text::LineFold    qw();
use Try::Tiny         qw( try catch );
use Unicode::GCString qw();
use URI               qw();
use URI::Escape       qw( uri_unescape );

use if $^O eq 'MSWin32', 'Win32::Console::ANSI';

use App::YTDL::YTConfig    qw( map_fmt_to_quality );
use App::YTDL::YTData      qw( get_data );
use App::YTDL::YTXML       qw( xml_to_entry_node );
use App::YTDL::GenericFunc qw( term_size unicode_trim encode_stdout_lax );

use constant {
    QUIT   => -1,
    DELETE => -2,
    APPEND => -3,
    REDO   => -4,
};


sub get_download_infos {
    my ( $opt, $info ) = @_;
    my ( $cols, $rows ) = term_size();
    print "\n\n\n", '=' x $cols, "\n\n", "\n" x $rows;
    print locate( 1, 1 ), cldown;
    say 'Dir  : ', $opt->{yt_video_dir};
    say 'Agent: ', $opt->{useragent} // '';
    print "\n";
    my @video_ids = sort {
           ( $info->{$b}{extractor}     // ''  ) cmp ( $info->{$a}{extractor}     // ''  )
        || ( $info->{$a}{list_id}       // ''  ) cmp ( $info->{$b}{list_id}       // ''  )
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
            $info = _get_print_info( $opt, $info, $video_id ) if $info->{$video_id}{youtube};
            ( $info, $print_array, $key_len ) = _format_print_info( $opt, $info, $video_id );
            print "\n";
            $opt->{up}++;
            binmode STDOUT, ':pop';
            print for map { encode_stdout_lax( $_ ) } @$print_array;
            binmode STDOUT, ':encoding(console_out)';
            $opt->{up} += @$print_array;
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
        if ( $info->{$video_id}{youtube} ) {
            my $status = $info->{$video_id}{status};
            if ( ! defined $status || $status ne 'ok' ) {
                _status_not_ok( $opt, $info, $video_id );
                next VIDEO;
            }
        }
        try { #
            my $edit;
            ( $info, $fmt, $edit ) = _choose_quality( $opt, $info, $fmt, $video_id );
            print up( $opt->{up} ), cldown;
            $opt->{up} = 0;
            if ( defined $edit ) {
                if ( $edit == QUIT ) {
                    print locate( 1, 1 ), cldown;
                    say "Quit";
                    exit;
                }
                if ( $edit == DELETE ) {
                    delete  $info->{$video_id};
                    if ( ! @video_ids ) {
                        print up( 2 ), cldown;
                        print "\n";
                    }
                }
                push    @video_ids, $video_id if $edit == APPEND;
                unshift @video_ids, $video_id if $edit == REDO;
            }
            else {
                $info->{$video_id}{video_url} = $info->{$video_id}{fmt_to_info}{$fmt}{url};
                $info->{$video_id}{file_name} = catfile( $opt->{yt_video_dir}, _get_filename( $opt, $info, $fmt, $video_id ) );
                $info->{$video_id}{count}     = ++$count;
                $info->{$video_id}{fmt}       = $fmt;
                $print_array->[0] =~ s/\n\z/ ($fmt)\n/;
                unshift @$print_array, sprintf "%*.*s : %s\n", $key_len, $key_len, 'video', $count;
                binmode STDOUT, ':pop';
                print for map { encode_stdout_lax( $_ ) } @$print_array;
                binmode STDOUT, ':encoding(console_out)';
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


sub _status_not_ok {
    my ( $opt, $info, $video_id ) = @_;
    $info->{$video_id}{status} //= 'undefined';
    my @keys    = ( 'title', 'video_id', 'status', 'errorcode', 'reason' );
    my $key_len = 10;
    my $s_tab   = $key_len + length( ' : ' );
    my $maxcols =  ( term_size() )[0] - $opt->{right_margin};
    my $col_max = $maxcols > $opt->{max_info_width} ? $opt->{max_info_width} : $maxcols;
    my $lf = Text::LineFold->new( %{$opt->{linefold}} );
    $lf->config( 'ColMax', $col_max );
    my $prompt = '  Status NOT OK!' . "\n\n";
    my $print_array;
    for my $key ( @keys ) {
        next if ! $info->{$video_id}{$key};
        $info->{$video_id}{$key} =~ s/\n+/\n/g;
        $info->{$video_id}{$key} =~ s/^\s+//;
        ( my $kk = $key ) =~ s/_/ /g;
        my $pr_key = sprintf "%*.*s : ", $key_len, $key_len, $kk;
        $prompt .= $lf->fold( '' , ' ' x $s_tab, $pr_key . $info->{$video_id}{$key} );
    }
    choose( [ 'Press ENTER' ], { prompt => $prompt } );
    delete $info->{$video_id};
    print up( $opt->{up} ), cldown;
    $opt->{up} = 0;
}


sub _get_print_info {
    my ( $opt, $info, $video_id ) = @_;
    $info = get_data( $opt, $info, $video_id );
    my $ua = LWP::UserAgent->new( agent => $opt->{useragent}, show_progress => 1 );
    my $info_url = URI->new( 'https://www.youtube.com/get_video_info' );
    $info_url->query_form( 'video_id' => $video_id );
    my $res = $ua->get( $info_url->as_string );
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


sub _format_print_info {
    my ( $opt, $info, $video_id ) = @_;
    my @keys = ( qw( title video_id ) );
    push @keys, 'extractor' if ! $info->{$video_id}{youtube};
    push @keys, qw( author duration raters avg_rating view_count published content description keywords );
    for my $key ( @keys ) {
        next if ! defined $info->{$video_id}{$key};
        $info->{$video_id}{$key} =~ s/\R/ /g;
    }
    my $key_len = 13;
    my $s_tab = $key_len + length( ' : ' );
    my ( $maxcols, $maxrows ) = term_size();
    $maxcols -= $opt->{right_margin};
    my $col_max = $maxcols > $opt->{max_info_width} ? $opt->{max_info_width} : $maxcols;
    my $lf = Text::LineFold->new( %{$opt->{linefold}} );
    $lf->config( 'ColMax', $col_max );
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


sub _get_filename {
    my ( $opt, $info, $fmt, $video_id ) = @_;
    my $title  = $info->{$video_id}{title};
    my $suffix = $info->{$video_id}{fmt_to_info}{$fmt}{ext};
    my $gcs_suff = Unicode::GCString->new( $suffix );
    my $gcs_fmt  = Unicode::GCString->new( $fmt );
    my $len = $opt->{max_len_f_name} - ( $gcs_suff->columns() + $gcs_fmt->columns() + 2 );
    my $file_name = unicode_trim( $title, $len );
    $file_name = $file_name . '_' . $fmt . '.' . $suffix;
    $file_name =~ s/\s/_/g;
    $file_name =~ s/^\s+|\s+\z//g;
    $file_name =~ s/^\.+//;
    #$file_name =~ s/[^\p{Word}.()]/-/g;
    $file_name =~ s/["\/\\:*?<>|]/-/g;
    # NTFS and FAT unsupported characters:  / \ : " * ? < > |
    return $file_name;
}


sub _choose_quality {
    my ( $opt, $info, $fmt, $video_id ) = @_;
    my @avail_fmts = @{$info->{$video_id}{fmt_list}};
    if ( ! @avail_fmts ) {
        my $ref = map_fmt_to_quality;
        for my $fmt ( sort keys %$ref ) {
            push @avail_fmts, $fmt if $info->{$video_id}{fmt_to_info}{$fmt}{url};
        }
        if ( ! @avail_fmts ) {
            my $prompt = 'video_id ' . $video_id . ': Error in fetching available fmts.' . "\n";
            $prompt .= 'Skipping video "' . $info->{$video_id}{title} . '".';
            choose( [ 'Press Enter to continue' ], { prompt => $prompt } );
            $fmt = DELETE;
            return $info, $fmt;
        }
    }
    my $skip_pq = $opt->{auto_quality} == 3 && ! $info->{$video_id}{youtube} ? 1 : 0;
    my ( $fmt_ok, $edit );
    if ( $opt->{auto_quality} == 4 ) {
        if ( defined $info->{$video_id}{default_fmt} ) {
            $fmt = $info->{$video_id}{default_fmt};
            $fmt_ok = 1;
        }
    }
    elsif ( $opt->{auto_quality} == 3 ) {
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
    elsif ( $opt->{auto_quality} == 2 || $skip_pq ) {
        if ( ! defined $opt->{aq} ) {
            ( $fmt, $edit ) = _set_fmt( $opt, $info, $video_id );
            $opt->{aq} = $fmt if $fmt >= 0;
            $fmt_ok = 1;
        }
        elsif ( any{ $_ eq $opt->{aq} } @avail_fmts ) {
            $fmt = $opt->{aq};
            $fmt_ok = 1;
        }
    }
    elsif ( $opt->{auto_quality} == 1 ) {
        if ( $info->{$video_id}{list_id} ) {
            my $aq = $info->{$video_id}{list_id};
            if ( ! defined $opt->{$aq} ) {
                ( $fmt, $edit ) = _set_fmt( $opt, $info, $video_id );
                if ( defined $fmt ) {
                    $opt->{$aq} = $fmt;
                    $fmt_ok = 1;
                }
            }
            elsif ( any{ $_ eq $opt->{$aq} } @avail_fmts ) {
                $fmt = $opt->{$aq};
                $fmt_ok = 1;
            }
        }
    }
    if ( ! $fmt_ok ) {
        ( $fmt, $edit ) = _set_fmt( $opt, $info, $video_id );
    }
    if ( ! defined $edit && ! $info->{$video_id}{fmt_to_info}{$fmt}{url} ) {
        my $prompt = 'video_id "' . $video_id . '": fmt ' . $fmt . ' not supported.';
        choose( [ 'Press ENTER to continue' ], { prompt => $prompt } );
        $edit = DELETE;
    }
    return $info, $fmt, $edit;
}


sub _set_fmt {
    my ( $opt, $info, $video_id ) = @_;
    my ( @choices, @format_ids );
    if ( $info->{$video_id}{youtube} ) {
        for my $fmt ( sort { $a <=> $b } @{$info->{$video_id}{fmt_list}} ) {
            push @choices, $info->{$video_id}{fmt_to_info}{$fmt}{format} . ' ' . $info->{$video_id}{fmt_to_info}{$fmt}{ext};
            push @format_ids, $fmt;
        }
    }
    else {
        for my $fmt ( sort @{$info->{$video_id}{fmt_list}} ) {
            push @choices, $info->{$video_id}{fmt_to_info}{$fmt}{format} . ' ' . $info->{$video_id}{fmt_to_info}{$fmt}{ext};
            push @format_ids, $fmt;
        }
    }
    my @pre = ( undef );
    print "\n";
    $opt->{up}++;
    my $fmt_res_idx = choose(
        [ @pre, @choices ],
        { prompt => 'Your choice: ', index => 1, order => 0, undef => 'Menu' }
    );
    my $fmt;
    my $edit;
    if ( ! $fmt_res_idx ) {
        my ( $delete, $append, $redo ) = ( 'Delete', 'Append', 'Redo' );
        my $choice = choose(
            [ undef, $delete, $append, $redo ],
            { prompt => 'Your choice: ', undef => $opt->{quit} }
        );
        $edit = QUIT   if ! defined $choice;
        $edit = DELETE if $choice eq $delete;
        $edit = APPEND if $choice eq $append;
        $edit = REDO   if $choice eq $redo;
    }
    else {
        $fmt_res_idx--;
        $fmt = $format_ids[$fmt_res_idx];
    }
    return $fmt, $edit;
}



1;


__END__
