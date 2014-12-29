package # hide from PAUSE
App::YTDL::Videos;

use warnings;
use strict;
use 5.010000;

use Exporter qw( import );
our @EXPORT_OK = qw( from_arguments_to_choices );

use List::MoreUtils        qw( any );
use Term::ANSIScreen       qw( :cursor :screen );
use Term::Choose           qw( choose );
use Term::ReadLine::Simple qw();
use URI                    qw();
use URI::Escape            qw( uri_unescape );

use App::YTDL::Data         qw( wrapper_get get_download_info_as_json );
use App::YTDL::Data_Extract qw( xml_to_entry_node add_entry_node_to_info_hash json_to_hash );


sub from_arguments_to_choices {
    my ( $opt, @ids ) = @_;
    my $info = {};
    my $invalid_char = $opt->{invalid_char};
    my $more = 0;
    for my $id ( @ids ) {
        if ( my $channel_id = _user_id( $opt, $id ) ) {
            my $tmp = _id_to_tmp_info_hash( $opt, 'CL', $channel_id );
            my $is_youtube = 1;
            _choose_videos_and_add_to_info_hash( $opt, $info, $tmp, $is_youtube );
        }
        elsif ( my $playlist_id = _playlist_id( $opt, $id ) ) {
            my $tmp = _id_to_tmp_info_hash( $opt, 'PL', $playlist_id );
            my $is_youtube = 1;
            _choose_videos_and_add_to_info_hash( $opt, $info, $tmp, $is_youtube );
        }
        elsif ( my $more_ids = _more_ids( $opt, $id ) ) {
            my $tmp = _more_url_to_tmp_info_hash( $opt, $more_ids );
            my $is_youtube = 1;
            _choose_videos_and_add_to_info_hash( $opt, $info, $tmp, $is_youtube );
        }
        elsif ( my $video_id = _video_id( $opt, $id )  ) {
            $info->{$video_id}{youtube} = 1;
        }
        else {
            my $tmp = _non_yt_id_to_tmp_info_hash( $opt, $id );
            my $is_youtube = 0;
            my @keys = keys %$tmp;
            if ( @keys == 1 ) {
                my $video_id = $keys[0];
                $info->{$video_id} = $tmp->{$video_id};
                $info->{$video_id}{youtube} = 0;
            }
            else {
                _choose_videos_and_add_to_info_hash( $opt, $info, $tmp, $is_youtube );
            }
        }
    }
    return $info;
}


sub _video_id {
    my ( $opt, $id ) = @_;
    my $invalid_char = $opt->{invalid_char};
    if ( ! $id ) {
        return;
    }
    if ( $id =~ m{^[\p{PerlWord}-]{11}\z} ) {
        return $id;
    }
    if ( $id !~ $opt->{yt_regexp} ) {
        return;
    }
    elsif ( $id =~ m{/.*?[?&;!](?:v|video_id)=([^$invalid_char]+)} ) {
        return $1;
    }
    elsif ( $id =~ m{/(?:e|v|embed)/([^$invalid_char]+)} ) {
        return $1;
    }
    elsif ( $id =~ m{#p/(?:u|search)/\d+/([^&?/]+)} ) {
        return $1;
    }
    elsif ( $id =~ m{youtu.be/([^$invalid_char]+)} ) {
        return $1;
    }
    return;
}

sub _playlist_id {
    my ( $opt, $id ) = @_;
    my $invalid_char = $opt->{invalid_char};
    if ( ! $id )                                        {
        return;
    }
    if ( $id =~ m{^p#(?:[FP]L)?([^$invalid_char]+)\z} ) {
        return $1;
    }
    if ( $id !~ $opt->{yt_regexp} ) {
        return;
    }
    elsif ( $id =~ m{/.*?[?&;!]list=([^$invalid_char]+)} ) {
        return $1;
    }
    elsif ( $id =~ m{^\s*([FP]L[\w\-]+)\s*\z} ) {
        return $1;
    }
    return;
}

sub _user_id {
    my ( $opt, $id ) = @_;
    my $invalid_char = $opt->{invalid_char};
    if ( ! $id ) {
        return;
    }
    if ( $id =~ m{^c#([^$invalid_char]+)\z} ) {
        return $1;
    }
    if ( $id !~ $opt->{yt_regexp} ) {
        return;
    }
    elsif ( $id =~ m{/user/([^$invalid_char]+)} ) {
        return $1;
    }
    elsif ( $id =~ m{/channel/([^$invalid_char]+)} ) { # ?
        return $1;
    }
    return;
}

sub _more_ids {
    my ( $opt, $id ) = @_;
    my $invalid_char = $opt->{invalid_char};
    if ( ! $id ) {
        return;
    }
    elsif ( $id !~ $opt->{yt_regexp} ) {
        return;
    }
    elsif ( uri_unescape( $id ) =~ m{youtu\.?be.*video_ids=([^$invalid_char]+(?:,[^$invalid_char]+)*)} ) {
        return $1;
    }
    return;
}


sub _id_to_tmp_info_hash {
    my( $opt, $type, $list_id ) = @_;
    printf "Fetching %s info ... \n", $type eq 'PL' ? 'playlist' : 'channel';
    my $url = URI->new( $type eq 'PL'
        ? 'https://gdata.youtube.com/feeds/api/playlists/' . $list_id
        : 'https://gdata.youtube.com/feeds/api/users/'     . $list_id . '/uploads'
    );
    my $tmp = {};
    my $start_index = 1;
    my $max_results = 50;
    my $count_e_nodes = $max_results;
    while ( $count_e_nodes == $max_results ) {  # or <link rel='next'>
        $url->query_form( 'start-index' => $start_index, 'max-results' => $max_results, 'v' => $opt->{yt_api_v} );
        $start_index += $max_results;
        my $res = wrapper_get( $opt, $url->as_string );
        if ( ! defined $res ) {
            my $err_msg = $type . ': ' . $list_id . '   ' . ( $start_index - $max_results ) . '-' . $start_index;
            push @{$opt->{error_get_download_infos}}, $err_msg;
            next;
        }
        my $xml = $res->decoded_content;
        my @e_nodes = xml_to_entry_node( $opt, $xml );
        $count_e_nodes = @e_nodes;
        for my $e_node ( @e_nodes ) {
            add_entry_node_to_info_hash( $opt, $tmp, $e_node, $type, $list_id );
        }
        last if ! $count_e_nodes;
    }
    if ( ! keys %$tmp ) {
        my $prompt = "No videos found: $type - $url";
        choose( [ 'Print ENTER' ], { prompt => $prompt } );
    }
    my $up = keys %$tmp;
    print up( $up + 2 ), cldown;
    return $tmp;
}


sub _more_url_to_tmp_info_hash {
    my ( $opt, $more_ids ) = @_;
    my $tmp = {};
    for my $video_id ( split /,/, $more_ids ) {
        my $url = URI->new( 'https://gdata.youtube.com/feeds/api/videos/' . $video_id );
        $url->query_form( 'v' => $opt->{yt_api_v} );
        my $res = wrapper_get( $opt, $url );
        if ( ! defined $res ) {
            my $err_msg = 'Video group: ' . $more_ids . ' - ' . $video_id . '   ' . $url;
            push @{$opt->{error_get_download_infos}}, $err_msg;
            next;
        }
        my $xml = $res->decoded_content;
        my $e_node = xml_to_entry_node( $opt, $xml );
        add_entry_node_to_info_hash( $opt, $tmp, $e_node );
    }
    return $tmp;
}


sub _non_yt_id_to_tmp_info_hash {
    my ( $opt, $id ) = @_;
    my $message = "Fetching download info: ";
    my $json_all = get_download_info_as_json( $opt, $id, $message );
    my $tmp = {};
    return $tmp if ! $json_all;
    for my $json ( split /\n+/, $json_all ) {
        json_to_hash( $json, $tmp );
    }
    return $tmp;
}


sub _choose_videos_and_add_to_info_hash {
    my ( $opt, $info, $tmp, $is_youtube ) = @_;
    my $regexp;
    my $ok     = 'ENTER';
    my $close  = 'Close';
    my $filter = '     FILTER';
    my $back   = '       BACK | 0:00:00';
    my $menu   = 'Choose:';
    my %chosen_video_ids;
    my @last_chosen_video_ids = ();

    FILTER: while ( 1 ) {
        my @pre = ( $menu );
        push @pre, $filter if ! length $regexp;
        my @videos;
        my @tmp_video_ids;
        my $index = $#pre;
        my $mark = [];
        my @video_ids = sort {
            ( $opt->{new_first} ? ( $tmp->{$b}{published} // '' ) cmp ( $tmp->{$a}{published} // '' )
                                : ( $tmp->{$a}{published} // '' ) cmp ( $tmp->{$b}{published} // '' ) )
                               || ( $tmp->{$a}{title}     // '' ) cmp ( $tmp->{$b}{title}     // '' ) } keys %$tmp;


        VIDEO_ID:
        for my $video_id ( @video_ids ) {
            ( my $title = $tmp->{$video_id}{title} ) =~ s/\s+/ /g;
            $title =~ s/^\s+|\s+\z//g;
            if ( length $regexp && $title !~ /$regexp/i ) {
                next VIDEO_ID;
            }
            $tmp->{$video_id}{from_list} = 1;
            $tmp->{$video_id}{youtube}   = $is_youtube;
            push @videos, sprintf "%11s | %7s  %10s  %s", $video_id, $tmp->{$video_id}{duration}, $tmp->{$video_id}{published}, $title;
            push @tmp_video_ids, $video_id;
            $index++;
            push @$mark, $index if any { $video_id eq $_ } keys %chosen_video_ids;
        }
        my $choices = [ @pre, @videos, undef ];
        my @idx = choose(
            $choices,
            { prompt => '', layout => 3, index => 1, default => 0, clear_screen => 1, mark => $mark,
              undef => $back, no_spacebar => [ 0 .. $#pre, $#$choices ] }
        );
        if ( ! defined $idx[0] ) {
            return;
        }
        my $choice = $choices->[$idx[0]];
        if ( ! defined $choice ) {
            return;
        }
        elsif ( $choice eq $menu ) {
            shift @idx;
            my @choices = ( undef );
            push @choices, $ok if length $regexp;
            push @choices, $close;
            my $menu_choice = choose(
                \@choices,
                { prompt => 'Choice: ', layout => 0, default => 0, undef => '<<' }
            );
            if ( ! defined $menu_choice ) {
                if ( length $regexp ) {
                    delete @{$info}{ @last_chosen_video_ids };
                    $regexp = '';
                    next FILTER;
                }
                else {
                    delete @{$info}{ keys %chosen_video_ids };
                    return;
                }
            }
            elsif ( $menu_choice eq $ok ) {
                @last_chosen_video_ids = ();
                for my $i ( @idx ) {
                    my $video_id = $tmp_video_ids[$i - @pre];
                    $info->{$video_id} = $tmp->{$video_id};
                    $chosen_video_ids{$video_id}++;
                    push @last_chosen_video_ids, $video_id;
                }
                for my $m ( @$mark ) {
                    if ( none { $m == $_ } @idx ) {
                        my $video_id = $tmp_video_ids[$m - @pre];
                        delete $chosen_video_ids{$video_id};
                        delete $info->{$video_id};
                    }
                }
                if ( length $regexp ) {
                    $regexp = '';
                    next FILTER;
                }
                else {
                    last FILTER;
                }
            }
            elsif ( $choice eq $close ) {
                next FILTER;
            }
        }
        elsif ( $choice eq $filter ) {
            my $trs = Term::ReadLine::Simple->new();
            $regexp = $trs->readline( "Regexp: " );
            next FILTER;
        }
        else {
            @last_chosen_video_ids = ();
            for my $i ( @idx ) {
                my $video_id = $tmp_video_ids[$i - @pre];
                $info->{$video_id} = $tmp->{$video_id};
                $chosen_video_ids{$video_id}++;
                push @last_chosen_video_ids, $video_id;
            }
            for my $m ( @$mark ) {
                if ( none { $m == $_ } @idx ) {
                    my $video_id = $tmp_video_ids[$m - @pre];
                    delete $chosen_video_ids{$video_id};
                    delete $info->{$video_id};
                }
            }
            if ( ! length $regexp ) {
                last FILTER;
            }
            $regexp = '';
            next FILTER;
        }
    }
}




1;


__END__
