package # hide from PAUSE
App::YTDL::YT_Quality;

use warnings;
use strict;
use 5.010000;

use Exporter qw( import );
our @EXPORT_OK = qw( map_fmt_to_quality );



sub map_fmt_to_quality {
    return [
        [ 13 => ' 176x144  3GP', ],
        [ 17 => ' 176x144  3GP', ],
        [ 36 => ' 320x240  3GP', ],

         [ 5 => ' 360x240  FLV', ], # 400
         [ 6 => ' 480x270  FLV', ],
        [ 34 => ' 640x360  FLV', ],
        [ 35 => ' 854x480  FLV', ],

        [ 18 => ' 640x360  MP4', ],
        [ 22 => '1280x720  MP4', ],
        [ 37 => '1920x1080 MP4', ],
        [ 38 => '4096x3072 MP4', ],

        [ 43 => ' 640x360  WebM', ],
        [ 44 => ' 854x480  WebM', ],
        [ 45 => '1280x720  WebM', ],
        [ 46 => '1920x1080 WebM', ],

        [ 82 => ' 640x360  MP4_3D', ],
        [ 83 => ' 854x480  MP4_3D', ],
        [ 84 => '1280x720  MP4_3D', ],
        [ 85 => '1920x1080 MP4_3D', ],

        [ 100 => ' 640x360  WebM_3D', ],
        [ 101 => ' 854x480  WebM_3D', ],
        [ 102 => '1280x720  WebM_3D', ],

         [ 92 => 'HLS  240  MP4', ],
         [ 93 => 'HLS  360  MP4', ],
         [ 94 => 'HLS  480  MP4', ],
         [ 95 => 'HLS  720  MP4', ],
         [ 96 => 'HLS 1080  MP4', ],
        [ 132 => 'HLS  240  MP4', ],
        [ 151 => 'HLS   72  MP4', ],

        [ 139 => 'DASH audio   48  M4A', ],
        [ 140 => 'DASH audio  128  M4A', ],
        [ 141 => 'DASH audio  256  M4A', ],

        [ 171 => 'DASH audio  128 WebM', ],
        [ 172 => 'DASH audio  256 WebM', ],

        [ 133 => 'DASH video  240  MP4', ],
        [ 134 => 'DASH video  360  MP4', ],
        [ 135 => 'DASH video  480  MP4', ],
        [ 136 => 'DASH video  720  MP4', ],
        [ 137 => 'DASH video 1080  MP4', ],
        [ 138 => 'DASH video 2160  MP4', ],

        [ 160 => 'DASH video  144  MP4',],
        [ 264 => 'DASH video 1440  MP4',],
        [ 298 => 'DASH video  720  MP4 h264 60fps', ],
        [ 299 => 'DASH video 1080  MP4 h264 60fps', ],
        [ 266 => 'DASH video 2160  MP4 h264', ],

        [ 167 => 'DASH video  360x640  WebM VP8', ],
        [ 168 => 'DASH video  480x854  WebM VP8', ],
        [ 169 => 'DASH video  720x1280 WebM VP8', ],
        [ 170 => 'DASH video 1080x1920 WebM VP8', ],
        [ 218 => 'DASH video  480x854  WebM VP8', ],
        [ 219 => 'DASH video  480x854  WebM VP8', ],

        [ 242 => 'DASH video  240 WebM', ],
        [ 243 => 'DASH video  360 WebM', ],
        [ 244 => 'DASH video  480 WebM', ],
        [ 245 => 'DASH video  480 WebM', ],
        [ 246 => 'DASH video  480 WebM', ],
        [ 247 => 'DASH video  720 WebM', ],
        [ 248 => 'DASH video 1080 WebM', ],
        [ 271 => 'DASH video 1440 WebM', ],
        [ 272 => 'DASH video 2160 WebM', ],

        [ 278 => 'DASH video  144 WebM VP9', ],
        [ 302 => 'DASH video  720 WebM VP9', ],
        [ 303 => 'DASH video 1080 WebM VP9', ],
    ];
}


1;


__END__
