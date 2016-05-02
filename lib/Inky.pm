use strict;
use warnings;
package Inky;

use Moo;
use strictures 2;
use namespace::clean;
use Mojo::DOM;
use Const::Fast;

# ABSTRACT: Inky templates, in Perl

const my $DEFAULT_SPACER_SIZE_PX => 16;
const my $DEFAULT_COLS           => 12;

has 'column_count'   => ( is => 'ro', default => sub { $DEFAULT_COLS } );
has '_component_tags' => ( is => 'ro', default => sub { return [qw<
    button row columns container callout inky block-grid menu item center
    spacer wrapper
>]});

sub _classes {
    my ($element, @classes) = @_;
    if ($element->attr('class')) {
        push @classes, split /\s+/xms, $element->attr('class');
    }
    return join q{ }, @classes;
}

my %COMPONENTS = (
    columns => sub {
        my ($self, $element) = @_;
        return $self->_make_column($element, 'columns');
    },
    row => sub {
        my ($self, $element, $inner) = @_;
        return sprintf '<table class="%s"><tbody><tr>%s</tr></tbody></table>',
            _classes($element, 'row'), $inner;
    },
    button => \&_make_button,
    container => sub {
        my ($self, $element, $inner) = @_;
        return sprintf '<table class="%s"><tbody><tr><td>%s</td></tr></tbody></table>',
            _classes($element, 'container'), $inner;
    },
    inky => sub {
        return '<tr><td><img src="https://raw.githubusercontent.com/arvida/emoji-cheat-sheet.com/master/public/graphics/emojis/octopus.png" /></tr></td>';
    },
    'block-grid' => sub {
        my ($self, $element, $inner) = @_;
        return sprintf '<table class="%s"><tr>%s</tr></table>',
            _classes($element, 'block-grid', join q{}, 'up-', $element->attr('up')),
            $inner;
    },
    menu => sub {
        my ($self, $element, $inner) = @_;
        my $center_attr = $element->attr('align') ? 'align="center"' : q{};
        return sprintf '<table class="%s"%s><tr><td><table><tr>%s</tr></table></td></tr></table>',
            _classes($element, 'menu'), $center_attr, $inner;
    },
    item => sub {
        my ($self, $element, $inner) = @_;
        return sprintf '<th class="%s"><a href="%s">%s</a></th>',
            _classes($element, 'menu-item'), $element->attr('href'), $inner;
    },
    center => \&_make_center,
    callout => sub {
        my ($self, $element, $inner) = @_;
        return sprintf '<table class="callout"><tr><th class="%s">%s</th><th class="expander"></th></tr></table>',
            _classes($element, 'callout-inner'), $inner;
    },
    spacer => sub {
        my ($self, $element, $inner) = @_;
        my $size = $element->attr('size') // $DEFAULT_SPACER_SIZE_PX;
        return sprintf '<table class="%s"><tbody><tr><td height="%dpx" style="font-size:%dpx;line-height:%dpx;">&#xA0;</td></tr></tbody></table>',
            _classes($element, 'spacer'), $size, $size, $size, $inner;
    },
    wrapper => sub {
        my ($self, $element, $inner) = @_;
        return sprintf '<table class="%s" align="center"><tr><td class="wrapper-inner">%s</td></tr></table>',
            _classes($element, 'wrapper'), $inner;
    },
);

sub _make_button {
    my ($self, $element, $inner) = @_;

    my $expander = q{};

    # If we have the href attribute we can create an anchor for the inner
    # of the button
    $inner = sprintf '<a href="%s">%s</a>', $element->attr('href'), $inner
        if $element->attr('href');

    # If the button is expanded, it needs a <center> tag around the content
    my @el_classes = split /\s+/xms, $element->attr('class') // '';
    if (scalar grep { $_ eq 'expand' || $_ eq 'expanded' } @el_classes) {
        $inner = sprintf '<center>%s</center>', $inner;
        $expander = qq!\n<td class="expander"></td>!;
    }

    # The . button class is always there, along with any others on the <button>
    # element
    return sprintf '<table class="%s"><tr><td><table><tr><td>%s</td></tr></table></td>%s</tr></table>',
        _classes($element, 'button'), $inner, $expander;
}

sub _make_center {
    my ($self, $element, $inner) = @_;

    if ($element->children->size > 0) {
        $element->children->each(sub {
            my ($e) = @_;
            $e->attr('align', 'center');
            my @classes = split /\s+/xms, $e->attr('class') // q{};
            $e->attr('class', join q{ }, @classes, 'float-center');
        });
        $element->find('item, .menu-item')->each(sub {
            my ($e) = @_;
            my @classes = split /\s+/xms, $e->attr('class') // q{};
            $e->attr('class', join q{ }, @classes, 'float-center');
        });
    }
    $element->attr('data-parsed', q{});
    return sprintf '%s', $element->to_string;
}

sub _component_factory {
    my ($self, $element) = @_;

    my $inner = $element->content;

    my $tag = $element->tag;
    return $COMPONENTS{$tag}->($self, $element, $inner)
        if exists $COMPONENTS{$tag};

    # If it's not a custom component, return it as-is
    return sprintf '<tr><td>%s</td></tr>', $inner;
}

sub _make_column {
    my ($self, $col) = @_;

    my $output   = q{};
    my $inner    = $col->content;
    my @classes  = ();
    my $expander = q{};

    # Add 1 to include current column
    my $col_count = $col->following->size
                  + $col->preceding->size
                  + 1;

    # Inherit classes from the <column> tag
    if ($col->attr('class')) {
        push @classes, split /\s+/xms, $col->attr('class');
    }

    # Check for sizes. If no attribute is provided, default to small-12.
    # Divide evenly for large columns
    my $small_size = $col->attr('small') || $self->column_count;
    my $large_size =  $col->attr('large')
                   || $col->attr('small')
                   || int($self->column_count / $col_count);

    push @classes, sprintf 'small-%s', $small_size;
    push @classes, sprintf 'large-%s', $large_size;

    # Add the basic "columns" class also
    push @classes, 'columns';

    # Determine if it's the first or last column, or both
    push @classes, 'first'
        if !$col->preceding('columns, .columns')->size;
    push @classes, 'last'
        if !$col->following('columns, .columns')->size;

    # If the column contains a nested row, the .expander class should not be
    # used. The == on the first check is because we're comparing a string
    # pulled from $.attr() to a number
    if ($large_size == $self->column_count && $col->find('.row, row')->size == 0) {
        $expander = qq!\n<th class="expander"></th>!;
    }

    # Final HTML output
    $output = <<'END';
    <th class="%s">
      <table>
        <tr>
          <th>%s</th>%s
        </tr>
      </table>
    </th>
END

    my $class = join q{ }, @classes;
    return sprintf $output, $class, $inner, $expander
}

sub release_the_kraken {
    my ($self, $html) = @_;

    my $dom = Mojo::DOM->new( $html );
    my $tags = join ', ',
        map { $_ eq 'center' ? "$_:not([data-parsed])" : $_ }
        @{ $self->_component_tags };

    while ($dom->find($tags)->size) {
        my $elem     = $dom->find($tags)->first;
        my $new_html = $self->_component_factory($elem);
        $elem->replace($new_html);
    }
    return $dom->to_string;
}

1;

__END__

=encoding utf-8

=head1 DESCRIPTION

A Perl version of the Inky template language, see
L<https://github.com/zurb/inky|https://github.com/zurb/inky>.

=head1 SYNOPSIS

    use Inky;
    my $html = '..';
    say Inky->new->release_the_kraken($html);

=head1 SUBROUTINES/METHODS

=method new

Creates a new L<Inky|Inky> object.

=method column_count

How many columns is the email supposed to have, defaults to 12 col layout

=method release_the_kraken

Given some HTML possibly containing Inky template elements, returns it
expanded.

=head1 CHANGES FROM NPM VERSION

Additional component tags aren't supported.

Differing amounts of columns are untested.
