package # hide from PAUSE
App::YTDL::Info;

use warnings;
use strict;
use 5.010000;

use Exporter qw( import );
our @EXPORT_OK = qw( get_download_infos );

use File::Spec::Functions qw( catfile catdir );

use List::MoreUtils   qw( any none first_index );
use Term::ANSIScreen  qw( :cursor :screen );
use Term::Choose      qw( choose );
use Unicode::GCString qw();

use if $^O eq 'MSWin32', 'Win32::Console::ANSI';

use App::YTDL::YT_Quality qw( map_fmt_to_quality );
use App::YTDL::Info_Print qw( linefolded_print_info );
use App::YTDL::Helper     qw( term_size unicode_trim encode_stdout_lax encode_fs );



sub get_download_infos {
    my ( $opt, $info ) = @_;
    my ( $cols, $rows ) = term_size();
    print "\n\n\n", '=' x $cols, "\n\n", "\n" x $rows;
    print locate( 1, 1 ), cldown;
    say 'Dir  : ', $opt->{video_dir};
    say 'Agent: ', $opt->{useragent} // '';
    print "\n";
    my @video_ids = sort {
           ( $info->{$b}{extractor_key} // '' ) cmp ( $info->{$a}{extractor_key} // '' )
        || ( $info->{$a}{playlist_id}   // '' ) cmp ( $info->{$b}{playlist_id}   // '' )
        || ( $info->{$a}{uploader_id}   // '' ) cmp ( $info->{$b}{uploader_id}   // '' )
        || ( $info->{$a}{upload_date}   // '' ) cmp ( $info->{$b}{upload_date}   // '' )
        || ( $info->{$a}{title}         // '' ) cmp ( $info->{$b}{title}         // '' )
    } keys %$info;
    my $fmt;
    my $count = 0;
    $opt->{up} = 0;

    VIDEO:
    while ( @video_ids ) {
        my $video_id = shift @video_ids;
        $count++;
        my $key_len = 13;
        my $print_array = linefolded_print_info( $opt, $info, $video_id, $key_len );
        my $status_not_ok;
        if ( defined $info->{$video_id}{status} && $info->{$video_id}{status} ne 'ok' ) { # $info->{$video_id}{youtube}
            $status_not_ok = 1;
            unshift @$print_array, sprintf "%*.*s : %s  %s\n", $key_len, $key_len, 'video', $count, 'Status NOT OK!';
        }
        print "\n";
        $opt->{up}++;
        binmode STDOUT, ':pop';
        print for map { encode_stdout_lax( $_ ) } @$print_array;
        binmode STDOUT, ':encoding(console_out)';
        $opt->{up} += @$print_array;
        print "\n";
        $opt->{up}++;
        if ( $status_not_ok ) {
            push @{$opt->{download_status_not_ok}}, $video_id . ' - ' . $info->{$video_id}{title};
            delete $info->{$video_id};
            $opt->{up} = 0;
            next VIDEO;
        }
        $fmt = _fmt_quality( $opt, $info, $fmt, $video_id );
        print up( $opt->{up} ), cldown;
        $opt->{up} = 0;
        if ( ! defined $fmt ) {
            my ( $delete, $append, $redo ) = ( 'Delete', 'Append', 'Redo' );
            # Choose
            my $choice = choose(
                [ undef, $delete, $append, $redo ],
                { prompt => 'Your choice: ', undef => 'QUIT' }
            );
            if ( ! defined $choice ) {
                print locate( 1, 1 ), cldown;
                say "Quit";
                exit;
            }
            elsif ( $choice eq $delete ) {
                delete  $info->{$video_id};
                if ( ! @video_ids ) {
                    print up( 2 ), cldown;
                    print "\n";
                }
            }
            elsif ( $choice eq $append ) {
                push @video_ids, $video_id;
            }
            elsif ( $choice eq $redo ) {
                unshift @video_ids, $video_id;
            }
            $count--;
            next VIDEO;
        }
        else {
            my $video_dir = $opt->{video_dir};
            if ( $opt->{extractor_dir} ) {
                if ( $info->{$video_id}{extractor_key} ) {
                    my $extractor_dir = $info->{$video_id}{extractor_key};
                    $extractor_dir =~ s/\s/_/g;
                    $video_dir = catdir $video_dir, $extractor_dir;
                    mkdir encode_fs( $video_dir ) or die $! if ! -d encode_fs( $video_dir );
                }
            }
            if ( $opt->{channel_dir} == 2 || $opt->{channel_dir} == 1 && $info->{$video_id}{from_list} ) {
                if ( $info->{$video_id}{uploader} ) {
                    my $channel_name = $info->{$video_id}{uploader};
                    $channel_name =~ s/\s/_/g;
                    $video_dir = catdir $video_dir, $channel_name;
                    mkdir encode_fs( $video_dir ) or die $! if ! -d encode_fs( $video_dir );
                }
            }
            $info->{$video_id}{video_url} = $info->{$video_id}{fmt_to_info}{$fmt}{url};
            $info->{$video_id}{file_name} = catfile( $video_dir, _get_filename( $opt, $info, $fmt, $video_id ) );
            $info->{$video_id}{count}     = $count;
            $info->{$video_id}{fmt}       = $fmt;
            $print_array->[0] =~ s/\n\z/ ($fmt)\n/;
            unshift @$print_array, sprintf "%*.*s : %s\n", $key_len, $key_len, 'video', $count;
            binmode STDOUT, ':pop';
            print for map { encode_stdout_lax( $_ ) } @$print_array;
            binmode STDOUT, ':encoding(console_out)';
            print "\n";
            if ( $opt->{max_channels} && $info->{$video_id}{youtube} && $info->{$video_id}{uploader_id} ) {
                my $channel    = $info->{$video_id}{uploader};
                my $channel_id = $info->{$video_id}{uploader_id};
                if ( none{ $channel_id eq ( split /,/, $_ )[1] } @{$opt->{channel_sticky}} ) {
                    my $idx = first_index { $channel_id eq ( split /,/, $_ )[1] } @{$opt->{channel_history}};
                    if ( $idx > -1 ) {
                        splice @{$opt->{channel_history}}, $idx, 1;
                    }
                    unshift @{$opt->{channel_history}}, sprintf "%s,%s", $channel, $channel_id;
                }
            }
        }
    }
    print "\n";
    if ( $opt->{max_channels} ) {
        while ( @{$opt->{channel_history}} > $opt->{max_channels} ) {
            pop @{$opt->{channel_history}};
        }
        open my $fh, '>:encoding(UTF-8)', encode_fs( $opt->{c_history_file} ) or die $!;
        for my $line ( @{$opt->{channel_history}} ) {
            say $fh $line;
        }
        close $fh;
    }
    $opt->{total_nr_videos} = $count;
    if ( ! $opt->{total_nr_videos} ) {
        print locate( 1, 1 ), cldown;
        say "No videos";
        exit;
    }
    return $opt, $info;
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



sub _fmt_quality {
    my ( $opt, $info, $fmt, $video_id ) = @_;
    my $auto_quality = $opt->{auto_quality};
    $auto_quality = 2 if $auto_quality == 3 && ! $info->{$video_id}{youtube};
    my $fmt_ok;
    if ( $auto_quality == 0 ) {
    }
    elsif ( $auto_quality == 1 && $info->{$video_id}{from_list} ) {
        my $list_id = $info->{$video_id}{playlist_id} // $info->{$video_id}{uploader_id};
        if ( $list_id ) {
            if ( ! defined $opt->{$list_id} ) {
                $fmt = _choose_fmt( $opt, $info, $video_id );
                return if ! defined $fmt;
                $opt->{$list_id} = $fmt;
            }
            else {
                $fmt = $opt->{$list_id};
            }
            $fmt_ok = 1;
        }
    }
    elsif ( $auto_quality == 2 ) {
        if ( ! defined $opt->{ap_key} ) {
            $fmt = _choose_fmt( $opt, $info, $video_id );
            return if ! defined $fmt;
            $opt->{ap_key} = $fmt;
        }
        else {
            $fmt = $opt->{ap_key};
        }
        $fmt_ok = 1;
    }
    elsif ( $auto_quality == 3 ) {
        my @pref_qualities = @{$opt->{preferred}//[]};
        for my $pq ( @pref_qualities ) {
            if ( any { $pq eq $_ } keys %{$info->{$video_id}{fmt_to_info}} ) {
                $fmt = $pq;
                $fmt_ok = 1;
                last;
            }
        }
        if ( ! $fmt_ok ) {
            print "\n";
            $opt->{up}++;
            say 'video_id: ' . $video_id .
                ! @pref_qualities
                ? ' - no preferred qualities found!'
                : ' - no matches between preferred fmts and available fmts!';
            $opt->{up}++;
        }
    }
    elsif ( $auto_quality == 4 && defined $info->{$video_id}{format_id} ) {
        $fmt = $info->{$video_id}{format_id};
        $fmt_ok = 1;
    }
    if ( ! $fmt_ok ) {
        $fmt = _choose_fmt( $opt, $info, $video_id );
        return if ! defined $fmt;
    }
    return $fmt;
}


sub _choose_fmt {
    my ( $opt, $info, $video_id ) = @_;
    my ( @choices, @format_ids );
    my @fmts;
    if ( $info->{$video_id}{youtube} ) {
        for my $fmt ( sort { $a <=> $b } keys %{$info->{$video_id}{fmt_to_info}} ) {
            my ( $fmt, $desc ) = split '\s*-\s*', $info->{$video_id}{fmt_to_info}{$fmt}{format};
            $desc = '' if ! $desc;
            push @choices, sprintf '%3s - %s %s', $fmt, $desc, $info->{$video_id}{fmt_to_info}{$fmt}{ext};
            push @format_ids, $fmt;
        }
    }
    else {
        for my $fmt ( sort { $a cmp $b } keys %{$info->{$video_id}{fmt_to_info}} ) {
            push @choices, $info->{$video_id}{fmt_to_info}{$fmt}{format} . ' ' . $info->{$video_id}{fmt_to_info}{$fmt}{ext};
            push @format_ids, $fmt;
        }
    }
    my @pre = ( undef );
    print "\n";
    $opt->{up}++;
    # Choose
    my $fmt_res_idx = choose(
        [ @pre, @choices ],
        { prompt => 'Your choice: ', index => 1, order => 1, undef => 'Menu' }
    );
    return if ! $fmt_res_idx;
    $fmt_res_idx -= @pre;
    my $fmt = $format_ids[$fmt_res_idx];
    return $fmt;
}



1;


__END__
