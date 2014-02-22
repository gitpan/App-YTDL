package # hide from PAUSE
App::YTDL::YTConfig;

use warnings;
use strict;
use 5.10.1;

use Exporter qw(import);
our @EXPORT_OK = qw(map_fmt_to_quality read_config_file options);

use File::Basename        qw(basename);
use File::Spec::Functions qw(catdir catfile);
use FindBin               qw($RealBin $RealScript);
use List::Util            qw(max);
use Pod::Usage            qw(pod2usage);

use JSON::XS;
use Text::LineFold;

use App::YTDL::GenericFunc qw(term_size encode_fs);

BEGIN {
    if ( $^O eq 'MSWin32' ) {
        require Term::Choose::Win32;
        Term::Choose::Win32::->import( 'choose' );
    } else {
        require Term::Choose;
        Term::Choose::->import( 'choose' );
    }
}


sub fmts_sorted {
    return [ 13, 17, 36, 5, 6, 34, 35, 18, 22, 37, 38, 82 .. 85, 43 .. 46, 100 .. 103 ];
}


sub map_fmt_to_quality {
    return {
        13 => ' 176x144  3GP',
        17 => ' 176x144  3GP',
        36 => ' 320x240  3GP',

         5 => ' 360x240  FLV',
         6 => ' 480x270  FLV',
        34 => ' 640x360  FLV',
        35 => ' 854x480  FLV',

        18 => ' 640x360  MP4',
        22 => '1280x720  MP4',
        37 => '1920x1080 MP4',
        38 => '4096x3072 MP4',

        43 => ' 640x360  WebM',
        44 => ' 854x480  WebM',
        45 => '1280x720  WebM',
        46 => '1920x1080 WebM',

        82 => ' 640x360  MP4_3D',
        83 => ' 854x480  MP4_3D',
        84 => '1280x720  MP4_3D',
        85 => '1920x1080 MP4_3D',

        100 => ' 640x360  WebM_3D',
        101 => ' 854x480  WebM_3D',
        102 => '1280x720  WebM_3D',
        103 => '1920x1080 WebM_3D',
    };
}


sub options {
    my ( $opt ) = @_;
    my $help         = "  HELP";
    my $show_path    = "  PATH";
    my $useragent    = "- UserAgent";
    my $overwrite    = "- Overwrite files";
    my $auto_fmt     = "- Set auto quality";
    my $preferred    = "- Preferred qualities";
    my $retries      = "- Download retries";
    my $logging      = "- Enable logging";
    my $info_width   = "- Max info width";
    my $auto_width   = "- Enable auto width";
    my $filename_len = "- Max filename length";
    my $len_kb_sec   = "- Digits 'k/s'";
    my %c_hash = (
        $help         => 'show_help_text',
        $show_path    => 'show_path',
        $useragent    => 'useragent',
        $overwrite    => 'overwrite',
        $auto_fmt     => 'auto_quality',
        $preferred    => 'preferred',
        $retries      => 'retries',
        $logging      => 'log_info',
        $info_width   => 'max_info_width',
        $auto_width    => 'auto_width',
        $filename_len => 'max_len_f_name',
        $len_kb_sec   => 'kb_sec_len',
    );
    my @choices = (
        $help,
        $show_path,
        $useragent,
        $overwrite,
        $auto_fmt,
        $preferred,
        $retries,
        $logging,
        $info_width,
        $auto_width,
        $filename_len,
        $len_kb_sec,
    );
    my $continue = '  ' . $opt->{continue};
    my $quit     = '  ' . $opt->{quit};

    OPTION: while ( 1 ) {
        # Choose
        print "\n";
        my $c_key = choose(
            [ undef, $continue, @choices ],
            { prompt => "Options:", layout => 3, clear_screen => 1, undef => $quit }
        );
        if ( ! defined $c_key ) {
            write_config_file( $opt, $opt->{config_file}, values %c_hash ) if $opt->{change};
            exit();
        }
        if ( $c_key eq $continue ) {
            write_config_file( $opt, $opt->{config_file}, values %c_hash ) if $opt->{change};
            delete $opt->{change};
            last OPTION;
        }
        my $choice = $c_hash{$c_key};
        if ( $choice eq "show_help_text" ) {
            pod2usage( { -exitval => 'NOEXIT', -verbose => 2 } );
        }
        elsif ( $choice eq "show_path" ) {
            my $bin         = 'bin';
            my $video_dir   = 'video dir';
            my $log_file    = 'log file';
            my $config_file = 'config file';
            my $path = {
                $bin         => catfile( $RealBin, $RealScript ),
                $video_dir   => $opt->{youtube_dir},
                $log_file    => $opt->{log_file},
                $config_file => $opt->{config_file},
            };
            my $keys = [ $bin, $video_dir, $log_file, $config_file ];
            my $len_key = 13;
            print_hash( $opt, $path, $keys, $len_key, ( term_size() )[0] );
        }
        elsif ( $choice eq "useragent" ) {
            my $prompt = 'Set the UserAgent';
            local_read_line( $opt, $choice, $prompt );
            $opt->{useragent} = 'Mozilla/5.0' if $opt->{useragent} eq '';
            $opt->{useragent} = ''            if $opt->{useragent} eq '""';
        }
        elsif ( $choice eq "overwrite" ) {
            my $prompt = 'Overwrite files';
            opt_yes_no( $opt, $choice, $prompt );
        }
        elsif ( $choice eq "log_info" ) {
            my $prompt = 'Enable info-logging';
            opt_yes_no( $opt, $choice, $prompt );
        }
        elsif ( $choice eq "auto_quality" ) {
            my $list = [
                'choose always manually',
                'keep choice for the respective Playlist/Channel if possible',
                'keep choice always if possible',
                'use preferred qualities'
            ];
            opt_choose_from_list( $opt, $choice, $list );
        }
        elsif ( $choice eq "preferred" ) {
            opt_choose_a_list( $opt, $choice, map_fmt_to_quality(), fmts_sorted() );
        }
        elsif ( $choice eq "retries" ) {
            my ( $min, $max ) = ( 0, 99 );
            my $prompt = 'Download retries';
            opt_number( $opt, $choice, $prompt, $min, $max );
        }
        elsif ( $choice eq "max_info_width" ) {
            my ( $min, $max ) = ( 40, 500 );
            my $prompt = 'Maximum Info width';
            opt_number( $opt, $choice, $prompt, $min, $max );
        }
        elsif ( $choice eq "auto_width" ) {
            my $prompt = 'Enable auto width';
            opt_yes_no( $opt, $choice, $prompt );
        }
        elsif ( $choice eq "max_len_f_name" ) {
            my ( $min, $max ) = ( 12, 300 );
            my $prompt = 'Maximum filename length';
            opt_number( $opt, $choice, $prompt, $min, $max );
        }
        elsif ( $choice eq "kb_sec_len" ) {
            my ( $min, $max ) = ( 3, 9 );
            my $prompt = 'Digits for "k/s" (download speed)';
            opt_number( $opt, $choice, $prompt, $min, $max );
        }
        else { die $choice }
    }
    return $opt;
}


sub print_hash {
    my ( $opt, $hash, $keys, $len_key, $maxcols ) = @_;
    my $s_tab   = $len_key + length( ' : ' );
    my $col_max = $maxcols - $s_tab;
    my $lf      = Text::LineFold->new( %{$opt->{line_fold}} );
    $lf->config( 'ColMax', $col_max );
    my @vals = ();
    for my $key ( @$keys ) {
        my $pr_key = sprintf "%*.*s : ", $len_key, $len_key, $key;
        my $text   = $lf->fold( '' , ' ' x $s_tab, $pr_key . $hash->{$key} );
        $text =~ s/\R+\z//;
        for my $val ( split /\R+/, $text ) {
            push @vals, $val;
        }
    }
    choose( [ @vals ], { layout => 3, clear_screen => 1 } );
}


sub local_read_line {
    my ( $opt, $section, $prompt ) = @_;
    my $current = $opt->{$section} // '';
    $prompt .= ' [' . $current . ']: ';
    print $prompt;
    my $string = <STDIN>;
    chomp $string;
    $opt->{$section} = $string;
    $opt->{change}++;
    return;
}


sub opt_yes_no {
    my ( $opt, $section, $prompt ) = @_;
    my ( $yes, $no ) = ( 'YES', 'NO' );
    my $current = $opt->{$section} ? $yes : $no;
    # Choose
    my $choice = choose(
        [ undef, $yes, $no ],
        { prompt => $prompt . ' [' . $current . ']:', layout => 1, undef => $opt->{s_back} }
    );
    return if ! defined $choice;
    $opt->{$section} = $choice eq $yes ? 1 : 0;
    $opt->{change}++;
    return;
}

sub opt_number {
    my ( $opt, $section, $prompt, $min, $max ) = @_;
    my $current = $opt->{$section};
    # Choose
    my $choice = choose(
        [ undef, $min .. $max ],
        { prompt => $prompt . ' [' . $current . ']:', layout => 1, justify => 1, order => 0, undef => $opt->{s_back} }
    );
    return if ! defined $choice;
    $opt->{$section} = $choice;
    $opt->{change}++;
    return;
}

sub opt_choose_from_list {
    my ( $opt, $section, $list ) = @_;
    my @options = ();
    my $len = length( scalar @$list );
    for my $i ( 0 .. $#$list ) {
        push @options, sprintf "%*d => %s", $len, $i, $list->[$i];
    }
    my $prompt = "$section [" . ( $opt->{$section} // '--' ) . "]";
    my $value = choose( [ undef, @options ], { prompt => $prompt, layout => 3, undef => $opt->{s_back} } );
    return if ! defined $value;
    $value = ( split / => /, $value )[0];
    $opt->{$section} = $value;
    $opt->{change}++;
    return;
}

sub opt_choose_a_list {
    my ( $opt, $section, $ref, $keys ) = @_;
    my $available = [];
    my $len_key = max map { length } @$keys;
    for my $key ( @$keys ) {
        push @$available, sprintf "%*d => %s", $len_key, $key, $ref->{$key};
    }
    my $current = $opt->{$section} // [];
    my $new     = [];
    my $key_cur = 'Current > ';
    my $key_new = '    New > ';
    my $l_k     = length $key_cur > length $key_new ? length $key_cur : length $key_new;
    my $lf      = Text::LineFold->new( %{$opt->{line_fold}} );
    $lf->config( 'ColMax', ( term_size() )[0] );
    while ( 1 ) {
        my $prompt = $key_cur . join( ', ', @$current ) . "\n";
        $prompt   .= $key_new . join( ', ', @$new )     . "\n\n";
        $prompt   .= 'Choose:';
        # Choose
        my $val = choose(
            [ undef, $opt->{confirm}, map( "  $_", @$available ) ],
            { prompt => $prompt, lf => [0,$l_k], layout => 3, clear_screen => 1, undef => $opt->{back} }
        );
        if ( ! defined $val ) {
            if ( @$new ) {
                $new = [];
                next;
            }
            else {
                return;
            }
        }
        if ( $val eq $opt->{confirm} ) {
            if ( @$new ) {
                $opt->{$section} = $new;
                $opt->{change}++;
            }
            return;
        }
        $val =~ s/^\s+//;
        $val = ( split / => /, $val )[0];
        push @$new, $val;
    }
}

sub write_config_file {
    my ( $opt, $file, @keys ) = @_;
    my $tmp = {};
    for my $section ( sort @keys ) {
        $tmp->{$section} = $opt->{$section};
    }
    write_json( $file, $tmp );
}


sub read_config_file {
    my ( $opt, $file ) = @_;
    my $tmp = read_json( $file );
    for my $section ( keys %$tmp ) {
        $opt->{$section} = $tmp->{$section};
    }
    return $opt;
}


sub write_json {
    my ( $file, $h_ref ) = @_;
    my $json = JSON::XS->new->pretty->encode( $h_ref );
    open my $fh, '>', encode_fs( $file ) or die $!;
    print $fh $json;
    close $fh;
}


sub read_json {
    my ( $file ) = @_;
    return {} if ! -f encode_fs( $file);
    open my $fh, '<', encode_fs( $file ) or die $!;
    my $json = do { local $/; <$fh> };
    close $fh;
    my $h_ref = JSON::XS->new->pretty->decode( $json ) if $json;
    return $h_ref;
}


1;


__END__
