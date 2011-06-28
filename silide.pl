#!/usr/bin/env perl

use 5.010;
use utf8;
use strict;
use warnings;
use autodie;
use FindBin qw($RealBin);
use lib "$RealBin/lib";
use File::Copy::Recursive qw(fcopy dircopy);
use File::Spec::Functions;
use File::Path qw(remove_tree);
use File::Slurp;
use Getopt::Long::Descriptive;
use YAML::Any qw(LoadFile);
use Const::Fast;
use App::Silide::MultiMarkdown;

const my $SILIDE_FILE => 'silide.yml';
const my $RESULT_FILE => 'index.html';
const my $CSS_DIR     => 'css';
const my $JS_DIR      => 'js';
const my @IMG_FILES   => qw(
    img/good.jpg
    img/qa.jpg
    img/thanks.gif
);

binmode STDIN,  ':utf8';
binmode STDOUT, ':utf8';

my ( $opt, $usage ) = describe_options(
    "%c %o ...",
    [
        'slide|s=s',
        "slide file (default: $SILIDE_FILE)",
        { default => $SILIDE_FILE },
    ],
    [
        'result=s',
        "result file (default: $RESULT_FILE)",
        { default => $RESULT_FILE },
    ],
    [
        'css=s', "css directory (default: $CSS_DIR)", { default => $CSS_DIR },
    ],
    [
        'js=s',
        "javascript directory (default: $JS_DIR)",
        { default => $JS_DIR },
    ],
    [ 'clean', 'remove result files' ],
    [],
    [ 'verbose|v', 'print extra stuff', { default => 0 } ],
    [ 'help|h',    'print usage message and exit' ],
);

print( $usage->text ), exit if $opt->help;
remove_tree( $opt->css, $opt->js, $opt->result, @IMG_FILES, ), exit
    if $opt->clean;

fcopy( catfile( $RealBin, $SILIDE_FILE ), $SILIDE_FILE )
    unless -e $SILIDE_FILE;
for my $img_file (@IMG_FILES) {
    fcopy( catfile( $RealBin, $img_file ), $img_file ) unless -e $img_file;
}

dircopy( catfile( $RealBin, $JS_DIR ),  $JS_DIR )  unless -e $JS_DIR;
dircopy( catfile( $RealBin, $CSS_DIR ), $CSS_DIR ) unless -e $CSS_DIR;

my $m = App::Silide::MultiMarkdown->new(
    tab_width     => 2,
    use_wikilinks => 0,
);

my $conf   = LoadFile( $opt->slide );
my $info   = $conf->{info};
my $color  = $conf->{color};
my $slides = $conf->{slides};

my $output = q{};
$output .= _get_header( $info, $color );

my $idx   = 0;
my $cover = {
    id      => 'landing',
    section => "# $info->{subject}",
};
$cover->{section} .= qq{\n#### by } . $info->{author} if $info->{author};
$cover->{section} .= qq{ <<} . $info->{email} . q{>>} if $info->{email};
$cover->{section} .= qq{\n## } . $info->{company}     if $info->{company};
for my $slide ( $cover, @$slides ) {
    next unless $slide;

    my $id   = q{};
    my $size = q{};

    if ( !ref $slide ) {
        ( my $name = $slide || q{} ) =~ s/\W//g;
        $id = sprintf( 'slide-%d-%s', $idx, $name );
    }
    else {
        ( my $name = $slide->{name} || q{} ) =~ s/\W//g;
        $id = $slide->{id} || sprintf( 'slide-%d-%s', $idx, $name );
        my $sectionclass = $slide->{sectionclass} || 'middle';

        given ( $slide->{size} ) {
            when ('--') { $size = "$sectionclass-mm" }
            when ('-')  { $size = "$sectionclass-m" }
            when ('0')  { $size = "$sectionclass-0" }
            when ('+')  { $size = "$sectionclass-p" }
            when ('++') { $size = "$sectionclass-pp" }
            default     { $size = "$sectionclass-0" }
        }
    }

    my $contents;
    if ( !ref $slide ) {
        my $sectionclass = 'middle';
        if ( $slide =~ s/^(<<|>>)?([-+]{0,2})// ) {
            my $align = $1;
            my $tag   = $2;

            given ($align) {
                when ('<<') { $sectionclass = 'left' }
                when ('>>') { $sectionclass = 'right' }
                default     { $sectionclass = 'middle' }
            }

            given ($tag) {
                when ('--') { $size = "$sectionclass-mm" }
                when ('-')  { $size = "$sectionclass-m" }
                when ('0')  { $size = "$sectionclass-0" }
                when ('+')  { $size = "$sectionclass-p" }
                when ('++') { $size = "$sectionclass-pp" }
                default     { $size = "$sectionclass-0" }
            }
        }

        $contents
            = qq|<section class='$sectionclass $size'>|
            . $m->markdown("# $slide")
            . qq|</section>|;
        $slide = {};
    }
    elsif ( $slide->{code} ) {
        my $desc    = $slide->{code}{desc} || q{};
        my $type    = $slide->{code}{type} || q{perl};
        my $data    = $slide->{code}{data} || q{};
        my $section = $slide->{section}    || q{};

        if ( $slide->{name} ) {
            $contents
                = '<header>'
                . $m->markdown("# $slide->{name}")
                . '</header>'
                . qq|<section class='smallerCode'>|
                . ( $desc ? $m->markdown("### $desc") : q{} )
                . qq|<pre class="brush: $type;">$data</pre>|
                . $m->markdown($section)
                . qq|</section>|;
        }
        else {
            $contents
                = qq|<section class='middle'>|
                . ( $desc ? $m->markdown("### $desc") : q{} )
                . qq|<pre class="brush: $type;">$data</pre>|
                . $m->markdown($section)
                . qq|</section>|;
        }
    }
    elsif ( $slide->{image} ) {
        my $desc    = $slide->{image}{desc} || q{};
        my $alt     = $slide->{image}{alt}  || q{};
        my $data    = $slide->{image}{data} || q{};
        my $attr    = $slide->{image}{attr} || q{};
        my $section = $slide->{section}     || q{};

        if ( $slide->{name} ) {
            $contents
                = '<header>'
                . $m->markdown("# $slide->{name}")
                . '</header>'
                . qq|<section class='smallerCode middle'>|
                . ( $desc ? $m->markdown("### $desc") : q{} )

                #. $m->markdown("![$alt]($data)")
                . $m->markdown(qq{![$alt][]\n\n[$alt]: $data "$alt" $attr})
                . $m->markdown($section)
                . qq|</section>|;
        }
        else {
            $contents
                = qq|<section class='middle'>|
                . ( $desc ? $m->markdown("### $desc") : q{} )
                . $m->markdown(qq{![$alt][]\n\n[$alt]: $data "$alt" $attr})
                . $m->markdown($section)
                . qq|</section>|;
        }
    }
    elsif ( !$slide->{header} && !$slide->{section} ) {
        $contents
            = qq|<section class='middle $size'>|
            . $m->markdown("# $slide->{name}")
            . qq|</section>|;
    }
    elsif ( !$slide->{header} && $slide->{section} ) {

        if ( $slide->{name} ) {
            my $sectionclass
                = $slide->{sectionclass}
                ? $slide->{sectionclass}
                : 'smallerCode';

            $contents
                = '<header>'
                . $m->markdown("# $slide->{name}")
                . '</header>'
                . qq|<section class='$sectionclass'>|
                . $m->markdown( $slide->{section} )
                . $m->markdown('----')
                . qq|</section>|;
        }
        else {
            $contents
                = qq|<section class='middle landing'>|
                . $m->markdown( $slide->{section} )
                . qq|</section>|;
        }
    }
    else {
        my $sectionclass
            = $slide->{sectionclass} ? $slide->{sectionclass}
            : $slide->{header}       ? 'smallerCode'
            :                          'middle';

        my $header
            = '<header>'
            . $m->markdown( $slide->{header} || q{} )
            . '</header>';

        my $section
            = qq|<section class='$sectionclass'>|
            . $m->markdown( $slide->{section} || q{} )
            . qq|</section>|;

        $contents = $slide->{header} ? $header . $section : $section;
    }

    $output .= <<"END_SLIDE";
        <!-- $id -->
        <div class='slide' id='$id'> $contents </div>
END_SLIDE

    ++$idx;
}

$output .= _get_footer();

if ( $opt->result eq '-' ) {
    print $output;
}
else {
    write_file( $opt->result, { binmode => ':utf8' }, $output );
}

sub _get_header {
    my ( $info, $color ) = @_;

    my $override_css = q{};
    if ($color) {
        for ( keys %$color ) {
            when ('strong') {
                $override_css .= qq|section strong { color: $color->{$_}; }|;
            }
            when ('em') {
                $override_css .= qq|section em { color: $color->{$_}; }|;
            }
            when ('background') {
                my $fg = $color->{$_}{fg};
                my $bg = $color->{$_}{bg};

                $override_css .= <<"END_OVERRIDE_CSS";
.presentation {
    display: block; overflow: hidden; background: #0D2833;
    background-color: $fg;
    background-image: -moz-radial-gradient(center, $bg, $fg);
    background-image: -o-radial-gradient(center, $bg, $fg);
    background-image: -webkit-gradient(radial,center center,center center,color-stop(0, $bg),color-stop(1, $fg));
    background-image: -webkit-radial-gradient(center, $bg, $fg);
    background-image: radial-gradient(center, $bg, $fg);
              filter: progid:DXImageTransform.Microsoft.gradient(startColorStr='$bg', EndColorStr='$fg', GradientType=1);
}
END_OVERRIDE_CSS
            }
        }
    }

    return <<"END_HEADER"
<!DOCTYPE html>
<!--[if lt IE 7 ]> <html lang="en" class="no-js ie6"> <![endif]-->
<!--[if IE 7 ]> <html lang="en" class="no-js ie7"> <![endif]-->
<!--[if IE 8 ]> <html lang="en" class="no-js ie8"> <![endif]-->
<!--[if IE 9 ]> <html lang="en" class="no-js ie9"> <![endif]-->
<!--[if (gt IE 9)|!(IE)]><!--> <html lang="en" class="no-js"> <!--<![endif]-->
<head>
  <meta charset='utf-8' />
  <meta content='IE=Edge;chrome=1' http-equiv='X-UA-Compatible' />
  <meta content='$info->{author} personal website' name='description' />
  <meta content='$info->{author}' name='author' />

  <title>$info->{subject} | by $info->{author}</title>

  <script src='js/modernizr-shim.min.js'></script>

  <!-- Syntax Highlighter -->
  <script type="text/javascript" src="js/shCore.js"></script>
  <script type="text/javascript" src="js/shBrushBash.js"></script>
  <script type="text/javascript" src="js/shBrushPerl.js"></script>
  <script type="text/javascript" src="js/shBrushJScript.js"></script>
  <script type="text/javascript" src="js/shBrushPlain.js"></script>
  <script type="text/javascript" src="js/shBrushXml.js"></script>
  <script type="text/javascript" src="js/shBrushSql.js"></script>
  <script type="text/javascript" src="js/shBrushDiff.js"></script>
  <script type="text/javascript" src="js/shBrushJava.js"></script>
  <script type="text/javascript" src="js/shBrushCpp.js"></script>
  <script type="text/javascript" src="js/shBrushYaml.js"></script>
  <script type="text/javascript" src="js/shBrushLatex.js"></script>
  <script type="text/javascript" src="js/shBrushIni.js"></script>

  <link type="text/css" rel="stylesheet" href="css/shCore.css" />
  <link type="text/css" rel="stylesheet" href="css/shThemeMidnight.css" />
  <link type="text/css" rel="stylesheet" href="css/main.css" />
  <style type="text/css">
$override_css
  </style>

</head>
<body>
  <div class='presentation'>
    <div id='presentation-counter'></div>
    <div class='slides'>
END_HEADER
}

sub _get_footer {
    return <<'END_FOOTER'
    </div>
  </div>
  <script charset='utf-8' src='js/jquery-1.4.4.min.js' type='text/javascript'></script>
  <!-- presentation -->
  <script charset='utf-8' src='js/slides.js' type='text/javascript'></script>
  <!--[if lt IE 9]>
    <script src="http://ajax.googleapis.com/ajax/libs/chrome-frame/1/CFInstall.min.js"></script>
    <script>CFInstall.check({ mode: "overlay" });</script>
  <![endif]-->

  <script type="text/javascript">
        SyntaxHighlighter.all();

        /*
        * https://bitbucket.org/alexg/syntaxhighlighter/issue/182/version-3-making-code-wrap
        */
        $(function(){
            // Line wrap back
            var shLineWrap = function(){
                $('.syntaxhighlighter').each(function(){
                    // Fetch
                    var $sh = $(this),
                        $gutter = $sh.find('td.gutter'),
                        $code = $sh.find('td.code')
                    ;
                    // Cycle through lines
                    $gutter.children('.line').each(function(i){
                        // Fetch
                        var $gutterLine = $(this),
                            $codeLine = $code.find('.line:nth-child('+(i+1)+')');
                        // Fetch height
                        var height = $codeLine.height()||0;
                        if ( !height ) {
                            height = 'auto';
                        }
                        else {
                            height = height += 'px important';
                        }
                        // Copy height over
                        $gutterLine.height(height);
                        console.debug($gutterLine.height(), height, $gutterLine.text(), $codeLine);
                    });
                });
            };
            
            // Line wrap back when syntax highlighter has done it's stuff
            var shLineWrapWhenReady = function(){
                if ( $('.syntaxhighlighter').length === 0 ) {
                    setTimeout(shLineWrapWhenReady,800);
                }
                else {
                    shLineWrap();
                }
            };
            
            // Fire
            shLineWrapWhenReady();
        });
  </script>

</body>
</html>
END_FOOTER
}
