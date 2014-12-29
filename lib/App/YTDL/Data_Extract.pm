package # hide from PAUSE
App::YTDL::Data_Extract;

use warnings;
use strict;
use 5.010000;

use Exporter qw( import );
our @EXPORT_OK = qw( xml_to_entry_node add_entry_node_to_info_hash json_to_hash );

use JSON        qw( decode_json );
use URI         qw();
use URI::Escape qw( uri_escape );
use XML::LibXML qw();

use App::YTDL::Helper qw( sec_to_time insert_sep );



sub _xml_node_to_xpc {
    my ( $node ) = @_;
    my $xpc = XML::LibXML::XPathContext->new( $node );
    $xpc->registerNs( 'xmlns', 'http://www.w3.org/2005/Atom' );
    $xpc->registerNs( 'media', 'http://search.yahoo.com/mrss/' );
    $xpc->registerNs( 'gd',    'http://schemas.google.com/g/2005' );
    $xpc->registerNs( 'yt',    'http://gdata.youtube.com/schemas/2007' );
    return $xpc;
}


sub xml_to_entry_node {
    my ( $opt, $xml ) = @_;
    my $doc = XML::LibXML->load_xml( string => $xml );
    my $root = $doc->documentElement();
    my $xpc = _xml_node_to_xpc( $root );
    if ( $xpc->exists( '/xmlns:feed/xmlns:entry' ) ) {
        my @nodes = $xpc->findnodes( '/xmlns:feed/xmlns:entry' ) if $xpc->exists( '/xmlns:feed/xmlns:entry' );
        return @nodes if @nodes;
    }
    else {
        my ( $node ) = $xpc->findnodes( '/xmlns:entry' );
        return $node if $node;
    }
    return;
}


sub add_entry_node_to_info_hash {
    my ( $opt, $info, $entry, $type, $list_id ) = @_;
    die '$entry node not defined!' if ! defined $entry;
    die 'empty $entry node!'       if ! $entry;
    my $xpc = _xml_node_to_xpc( $entry );
    my $uri = URI->new( $xpc->findvalue( './media:group/media:player/@url' ) );
    my %params = $uri->query_form;
    my $video_id = uri_escape( $params{v} );
    die 'no video_id!' if ! $video_id;
    my $title       = $xpc->findvalue( './media:group/media:title' );
    my $description = $xpc->findvalue( './media:group/media:description' );
    my $keywords    = $xpc->findvalue( './media:group/media:keywords' );
    my $author      = $xpc->findvalue( './xmlns:author/xmlns:name' );
    my $content     = $xpc->findvalue( './xmlns:content' );
    my $published   = $xpc->findvalue( './xmlns:published' );
    my $seconds     = $xpc->findvalue( './media:group/yt:duration/@seconds' );
    my $avg_rating  = $xpc->findvalue( './gd:rating/@average' );
    my $num_raters  = $xpc->findvalue( './gd:rating/@numRaters' );
    my $view_count  = $xpc->findvalue( './yt:statistics/@viewCount' );
    my $author_uri  = $xpc->findvalue( './xmlns:author/xmlns:uri' );
    #my $updated     = $xpc->findvalue( './xmlns:updated' );
    $info->{$video_id} = {
        uploader    => $author,
        author_uri  => $author_uri,
        avg_rating  => $avg_rating,
        content     => $content,
        description => $description,
        keywords    => $keywords,
        duration    => $seconds,
        upload_date => $published,
        raters      => $num_raters,
        title       => $title,
        video_id    => $video_id,
        view_count  => $view_count,
    };
    if ( $info->{$video_id}{author_uri} =~ m|/users/([^$opt->{invalid_char}]+)| ) {
        $info->{$video_id}{uploader_id} = $1;
    }
    if ( $info->{$video_id}{upload_date} =~ /^(\d\d\d\d-\d\d-\d\d)T/ ) {
        $info->{$video_id}{published} = $1;
    }
    if ( defined $type && $type eq 'PL' ) {
        $info->{$video_id}{playlist_id} = $list_id;
    }
    _prepare_info_hash( $info, $video_id );
}


sub json_to_hash {
    my ( $json, $tmp ) = @_;
    my $h_ref = decode_json( $json );
    my $formats  = {};
    for my $format ( @{$h_ref->{formats}} ) {
        my $fmt = $format->{format_id};
        $formats->{$fmt}{ext}         = $format->{ext};
        $formats->{$fmt}{format}      = $format->{format};
        $formats->{$fmt}{format_note} = $format->{format_note};
        $formats->{$fmt}{height}      = $format->{height};
        $formats->{$fmt}{width}       = $format->{width};
        $formats->{$fmt}{url}         = $format->{url};
    }
    my $video_id = $h_ref->{id} // $h_ref->{title};
    $tmp->{$video_id}{video_id} = $video_id;
    my @keys = ( qw( uploader categories uploader_id description format_id dislike_count dislike_count
                     duration extractor extractor_key like_coun playlist_id title upload_date view_count ) );
                     # age_limit annotations fulltitle playlist stitle
    for my $key ( @keys ) {
        if ( defined $h_ref->{$key} ) {
            $tmp->{$video_id}{$key} = $h_ref->{$key};
        }
    }
    if ( $tmp->{$video_id}{upload_date} && $tmp->{$video_id}{upload_date} =~ /^(\d{4})(\d{2})(\d{2})\z/ ) {
            $tmp->{$video_id}{published} = $1 . '-' . $2 . '-' . $3;
    }
    $tmp->{$video_id}{fmt_to_info} = $formats;
    _prepare_info_hash( $tmp, $video_id );
    if ( defined $tmp->{$video_id}{extractor_key} && $tmp->{$video_id}{extractor_key} =~ /^youtube\z/i ) {
        $tmp->{$video_id}{youtube} = 1;
    }
    return;
}


sub _prepare_info_hash {
    my ( $info, $video_id ) = @_;
    if ( $info->{$video_id}{duration} ) {
        if ( $info->{$video_id}{duration} =~ /^[0-9]+\z/ ) {
            $info->{$video_id}{duration} = sec_to_time( $info->{$video_id}{duration}, 1 );
        }
    }
    else {
        $info->{$video_id}{duration} = '-:--:--';
    }
    if ( ! $info->{$video_id}{published} ) {
        if ( $info->{$video_id}{upload_date} ) {
            $info->{$video_id}{published} = $info->{$video_id}{upload_date};
        }
        else {
            $info->{$video_id}{published} = '0000-00-00';
        }
    }
    if ( $info->{$video_id}{uploader_id} ) {
        if ( ! $info->{$video_id}{uploader} ) {
            $info->{$video_id}{uploader} = $info->{$video_id}{uploader_id};
        }
        else {
            if ( $info->{$video_id}{uploader} ne $info->{$video_id}{uploader_id} ) {
                $info->{$video_id}{uploader} .= ' (' . $info->{$video_id}{uploader_id} . ')';
            }
        }
    }
    else {
        $info->{$video_id}{uploader_id} = $info->{$video_id}{playlist_id};
    }
    if ( $info->{$video_id}{like_count} && $info->{$video_id}{dislike_count} ) {
        if ( ! $info->{$video_id}{raters} ) {
            $info->{$video_id}{raters} = $info->{$video_id}{like_count} + $info->{$video_id}{dislike_count};
        }
        if ( ! $info->{$video_id}{avg_rating} ) {
            $info->{$video_id}{avg_rating} = $info->{$video_id}{like_count} * 5 / $info->{$video_id}{raters};
        }
    }

    if ( $info->{$video_id}{avg_rating} ) {
        $info->{$video_id}{avg_rating} = sprintf "%.2f", $info->{$video_id}{avg_rating};
    }
    if ( $info->{$video_id}{raters} ) {
        $info->{$video_id}{raters} = insert_sep( $info->{$video_id}{raters} );
    }
    if ( $info->{$video_id}{view_count} ) {
        $info->{$video_id}{view_count} = insert_sep( $info->{$video_id}{view_count} );
    }
    if ( defined $info->{$video_id}{extractor} || defined $info->{$video_id}{extractor_key} ) {
        $info->{$video_id}{extractor}     = $info->{$video_id}{extractor_key} if ! defined $info->{$video_id}{extractor};
        $info->{$video_id}{extractor_key} = $info->{$video_id}{extractor}     if ! defined $info->{$video_id}{extractor_key};
    }
}





1;


__END__
