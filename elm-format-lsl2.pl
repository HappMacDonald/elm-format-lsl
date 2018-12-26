#!/bin/perl
use strict;
use warnings;
use Data::Dumper;
use constant { TRUE => 1, FALSE => 0 };
use constant { VERSION => "0.0.1" };

my $symbols, $inputFH, $inputLine;
my $inputRow = 0;
my $inputColumn = 0;

my $lexemeTemplates =
{ CommentSingleLine => qr(\/\/)
, CommentMultiLineBegin => qr(\/\*)
, CommentMultiLineEnd => qr(\*\/)
, Newline => qr([\r\n]+)
, Whitespace => qr(\s+)
, BlockBegin => qr(\{)
, BlockEnd => qr(\})
, ParenBegin => qr(\()
, ParenEnd => qr(\))
, BracketBegin => qr(\[)
, BracketEnd => qr(\])
, StatementEnd => qr(\;)
, Name => qr([a-zA-Z_][a-zA-Z_0-9]*)
, UnaryOperators => qr(-|!|~)
, IncrementDecrement => qr(--|\+\+)
, Assignment => qr([+*/%-]?=)
, BinaryOperators => # Assignment not included
  qr
  ( [+*/%-] # Arithmetic
  | == #Comparison
  | !=
  | [<>]=?
  | \|\|? #Bitwise and Logical
  | &&?
  | ^
  | \<\<
  | >>
  )x
, Type => qr(integer|string|list|vector|rotation)
};

$lexemeTemplates =
{ %$lexemeTemplates
, ( StateDeclaration => LexemeTemplate('default | state Name')
  , TypeCast => LexemeTemplate('ParenBegin Type ParenEnd')
  )
};

sub LexemeTemplate
{ my $template = shift;
  $template =~
    s/(^| )([A-Z][a-zA-Z]+)/
      ($2 eq 'Whitespace'
      ?$lexemeTemplates->{Whitespace}
      :$lexemeTemplates->{$2} .'?'. $lexemeTemplates->{$2}
    /eg;
#print "!$template!\n";
  qr($template)x;
}

sub ParseProgram
{ my $symbolIndex = 0;
  $symbolIndex = IgnoreWhitespace($symbolIndex);
  while(ParseAccept('Type', $symbolIndex++))
  { $symbolIndex = IgnoreWhitespace($symbolIndex);
    ParseExpect('Name', $symbolIndex++);
    $symbolIndex = IgnoreWhitespace($symbolIndex);
    if(ParseAccept('ParenBegin', $symbolIndex++))
    { ParseFunction();
      $symbolIndex = 0;
    } else
    { ParseVariableDeclaration();
      $symbolIndex = 0;
    }
  }
  $symbolIndex = IgnoreWhitespace($symbolIndex);
  while(!ParseAccept('EOF', $symbolIndex++))
  { ParseState();
    $symbolIndex = 0;
  }
}

sub ParseExpression
{
}

sub ParseVariableDeclaration
{
}

sub ParseFunction
{
}

sub ParseState
{
}

sub WriteSymbol
{ my $whitespace = shift;
  my $symbolIndex = shift;
  if(defined $symbol)
  { print $whitespace . $symbol->{content};
    splice $symbols, 0, $symbolIndex+1; # Discard topmost symbols up to and including $symbolIndex.
  }
}

sub ReadSymbol
{ my $symbolIndex = shift;
  while(!defined($symbols->[$symbolIndex]));
  {
    if($inputLine eq '') # Blank at symbol read means end of line reached.
    { $inputRow++;
      $inputColumn = 0;
      $inputLine = readline <$inputFH> || die "Reading from STDIN failed at line $inputRow: $!";
      return({ 'template' => 'EOF', symbolContent => '' })
        unless($inputLine); # Blank right after a file read means end of file reached.
    }
    for $template (keys %$lexemeTemplates)
    { if($inputLine =~ s/(?<symbolContent>$lexemeTemplates->{$template}))//)
      { my $symbol =
        { template => $template
        , content => $+{symbolContent}
        };
        push $symbols, $symbol;
        $inputColumn += $+{symbolContent};
      }
    }
  }
  return $symbols->[$symbolIndex];
}

sub ParseAccept
{ my $testTemplate = shift;
  my $symbolIndex = shift;
  return( (ReadSymbol($symbolIndex))->{template} eq $testTemplate );
}

sub ParseExpect
{ my $testTemplates = shift;
  my $symbolIndex = shift;
  return(ParseExpect([$testTemplates], $symbolIndex)) if(ref($testTemplates) eq '');
  die("Bad test templates passed to ParseExpect: ". Dumper($testTemplates))
    unless(ref($testTemplates) eq 'ARRAY');
  foreach $testTemplate (@$testTemplates)
  { if(ParseAccept($testTemplate, $symbolIndex))
    { return TRUE;
    }
  }
  my $symbol = ReadSymbol($symbolIndex);
  die("Unexpected $symbol->{template} Symbol '$symbol->{content}' found at  ($inputRow, $inputColumn).");
}

ParseIgnore
{ my $testTemplates = shift;
  my $symbolIndex = shift;
  return(ParseIgnore([$testTemplates], $symbolIndex)) if(ref($testTemplates) eq '');
  die("Bad test templates passed to ParseIgnore: ". Dumper($testTemplates))
    unless(ref($testTemplates) eq 'ARRAY');
  foreach $testTemplate (@$testTemplates)
  { if(ParseAccept($testTemplate, $symbolIndex))
    { if($symbolIndex == 0)
      { shift $symbols;
      } else
      { $symbolIndex++;
      }
      return ParseIgnore($testTemplates, $symbolIndex);
    }
  }
  return $symbolIndex;
}

IgnoreWhitespace
{ my $symbolIndex = shift;
  return ParseIgnore('WhiteSpace', $symbolIndex);
}

open($inputFH, "<", STDIN);
ParseProgram();
close $inputFH;
