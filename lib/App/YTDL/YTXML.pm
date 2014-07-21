package # hide from PAUSE
App::YTDL::YTXML;

use warnings;
use strict;
use 5.010001;

use Exporter qw( import );
our @EXPORT_OK = qw( xml_to_entry_node  entry_nodes_to_video_ids entry_node_to_info_hash );

use URI         qw();
use URI::Escape qw( uri_escape );
use XML::LibXML qw();

use App::YTDL::GenericFunc qw( sec_to_time insert_sep );


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


sub entry_nodes_to_video_ids {
    my ( $entry_nodes ) = @_;
    my @video_ids;
    for my $entry ( @$entry_nodes ) {
        my $xpc = _xml_node_to_xpc( $entry );
        my @nodes = $xpc->findnodes( './media:group/media:player[@url]' );
        for my $node ( @nodes ) {
            my $url = URI->new( $node->getAttribute( 'url' ) );
            my %params = $url->query_form;
            push @video_ids, uri_escape( $params{v} );
        }
    }
    return @video_ids;
}


sub entry_node_to_info_hash {
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
    my $updated     = $xpc->findvalue( './xmlns:updated' );
    $info->{$video_id} = {
        author          => $author,
        author_uri      => $author_uri,
        avg_rating      => $avg_rating,
        content         => $content,
        description     => $description,
        keywords        => $keywords,
        duration_raw    => $seconds,
        published_raw   => $published,
        raters          => $num_raters, # num_raters
        title           => $title,
        updated         => $updated,
        video_id        => $video_id,
        view_count      => $view_count,
    };
    $info->{$video_id}{list_id} = $list_id;
    $info->{$video_id}{youtube} = 1;
    $info = _prepare_info_hash( $opt, $info, $video_id, $type, $list_id );
    return $info;
}


sub _prepare_info_hash {
    my ( $opt, $info, $video_id, $type, $list_id ) = @_;
    if ( $type eq 'PL' ) {
        $info->{$video_id}{playlist_id} = $list_id;
    }
    if ( ! $info->{$video_id}{duration_raw} || $info->{$video_id}{duration_raw} !~ /^[0-9]+\z/) {
        $info->{$video_id}{duration_raw} = 86399;
    }
    $info->{$video_id}{duration} = sec_to_time( $info->{$video_id}{duration_raw}, 1 );
    if ( $info->{$video_id}{published_raw} ) {
        if ( $info->{$video_id}{published_raw} =~ /^(\d\d\d\d-\d\d-\d\d)T/ ) {
            $info->{$video_id}{published} = $1;
        }
        else {
            $info->{$video_id}{published} = '0000-00-00';
        }
    }
    if ( $info->{$video_id}{author_uri} =~ m|/users/([^$opt->{invalid_char}]+)| ) {
        $info->{$video_id}{channel_id} = $1;
        if ( ! $info->{$video_id}{author} ) {
            $info->{$video_id}{author} = $info->{$video_id}{channel_id};
        }
        else {
            if ( $info->{$video_id}{author} ne $info->{$video_id}{channel_id} ) {
                $info->{$video_id}{author} .= ' (' . $info->{$video_id}{channel_id} . ')';
            }
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
    return $info;
}


1;


__END__
