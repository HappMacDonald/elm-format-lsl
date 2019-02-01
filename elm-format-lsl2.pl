#!/bin/perl
use strict;
use warnings;
use Data::Dumper;
use open qw(:std :utf8);
use constant { TRUE => 1, FALSE => 0 };
use constant { VERSION => "0.0.1" };

=pod
## Production notes

OK, now I have to define how Expressions work. :S
That sounds HAAAARD xD
=cut

my($symbols, $inputLine, $symbolIndex);
my $indent = 0;
my $inputRow = 0;
my $inputColumn = 0;
my $breakflag = FALSE;

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
, Comma => qr(,)
, DoubleQuote => qr(")
, NumberLiteral => qr([-+]?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)
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
  | \^
  | \<\<
  | >>
  )x
, Type => qr(integer|string|list|vector|rotation)
};

# Set Lexeme Keywords
( sub
  { while(my $keyword = shift)
    { $lexemeTemplates->{ucfirst($keyword)} = qr($keyword);
    }
  }
)->(qw(return if while do else for jump));

$lexemeTemplates =
{ %$lexemeTemplates
, ( StateDeclaration => LexemeTemplate('default | state Name')
  , TypeCast => LexemeTemplate('ParenBegin Type ParenEnd')
  )
};

# Lexemes will be checked in order, beginning with this list in this order.
# So first item here will be first lexeme checked.
my $lexemePreList =
[ qw( Type
      Whitespace
  )
];

# Lexemes will be checked in order, ENDING with this list in this order.
# So LAST item here will be last lexeme checked.
my $lexemePostList =
[ qw( Name
  )
];

# Thus, this becomes the final ordering of all lexemes.
my $lexemeOrderHash = {};

#custom scope limiter
{
  my $index = 0;

  foreach my $template (@$lexemePreList, keys %$lexemeTemplates)
  { if(!defined $lexemeOrderHash->{$template})
    {
      $lexemeOrderHash->{$template} = $index++;
    }
  }
  foreach my $template (@$lexemePostList)
  { # Not skipping items already accounted for.
    # Warning: this will swiss cheese the list a little bit,
    # so your algos need to be tolerant of a swiss-cheese
    # ordering.
    $lexemeOrderHash->{$template} = $index++;
  }
}

my $lexemeOrder = 
[ sort
    {$lexemeOrderHash->{$a} <=> $lexemeOrderHash->{$b}}
    keys %$lexemeOrderHash
];

sub LexemeTemplate
{ my $template = shift;
  $template =~
    s/(^| )([A-Z][a-zA-Z]+)/
      ($2 eq 'Whitespace')
      ?($lexemeTemplates->{Whitespace})
      :($lexemeTemplates->{$2} .'?'. $lexemeTemplates->{$2})
    /eg;
#print "!$template!\n";
  qr($template)x;
}

sub ParseProgram
{ $symbolIndex = 0; # Forget lookahead
  IgnoreWhitespace();
  while(!ParseAccept('State'))
  { 
# puts("A");
    if(ParseAccept('Type'))
    { 
# puts("B");
      IgnoreWhitespace();
# puts("C");
      if(ParseAccept('ParenBegin'))
      { 
# puts("D");
        ParseFunction();
      } else
      { 
# puts("E");
        ParseVariableDeclaration();
# puts("F");
        ParseStatementEnd();
# puts("I");
      }
    } else
    { 
# puts("G");
      ParseExpect('Name', "Program header, user function returning void");
# puts("H");
      ParseFunction();
# puts("J");
    }
# puts("K");
    IgnoreWhitespace();
# puts("L");
  }
# puts("M");
  IgnoreWhitespace();
# puts("N");
  while(!ParseAccept('EOF'))
  { 
# puts("O");
    ParseState();
# puts("P");
  }
# puts("Q");
  IgnoreWhitespace();
die("DONE");
}

sub ParseExpression
{ $symbolIndex = 0; # Forget lookahead
  ParseExpect('Expression', "TODO expression"); # TODO
}

sub ParseStatementEnd
{ $symbolIndex = 0; # Forget lookahead
  ParseExpect('StatementEnd', "End of a statement");
  WriteSymbol(''); # Just statement end
  WriteSymbol("\n"); # Just newline
}

sub ParseVariableDeclaration
{ $symbolIndex = 0; # Forget lookahead
# puts("EA");
  ParseExpect('Type', "Variable Declaration");
# puts("EB");
  WriteSymbol(RenderIndent()); # indent + type
# puts("EB");
  IgnoreWhitespace();
# puts("EC");
  ParseExpect('Name', "Variable Declaration");
# puts("ED");
  WriteSymbol(' '); # space + name
# puts("EE");
  IgnoreWhitespace();
# puts("EF");
  ParseExpect('Assignment', "Variable Declaration");
# puts("EG");
  WriteSymbol(' '); # space + assignment operator
# puts("EH");
# $breakflag = TRUE;
  IgnoreWhitespace();
# puts("EI");
  WriteSymbol("\n"); # Just newline
# puts("EJ");
  ++$indent;
  WriteSymbol(RenderIndent()); # Just new indent
# puts("EK");
  ParseExpression(); # Consume expression
# puts("EL");
  --$indent;
  return; # caller must end statement for us
}

sub ParseStatement
{ $symbolIndex = 0; # Forget lookahead
  if(ParseAccept('Type'))
  { ParseVariableDeclaration();
    return;
  }
  if(ParseAccept('Return'))
  { WriteSymbol(RenderIndent()); # indent + return
    IgnoreWhitespace();
    if(ParseAccept('StatementEnd'))
    { $symbolIndex = 0; # Forget lookahead
      return; # caller must end statement for us
    }
    ParseExpect('ParenBegin', "Return statement parenthesized value");
    WriteSymbol(''); # Just (
    ParseExpression();
    ParseExpect('ParenEnd', "Return statement parenthesized value");
    return; # caller must end statement for us
  }
  ParseExpect('Statement', "TODO Statement"); # TODO
}

sub ParseFunction
{ $symbolIndex = 0; # Forget lookahead
  # NOTE: $indent may be 0 for user functions or 1 for events
  IgnoreWhitespace();
  if(ParseAccept('Type'))
  { WriteSymbol(RenderIndent()); # indent + type
    IgnoreWhitespace();
    WriteSymbol(' '); # just space
  } else
  { WriteSymbol(RenderIndent()); # Just indent
  }
  ParseExpect('Name', "Function");
  WriteSymbol(''); # Just name
  IgnoreWhitespace();
  ParseExpect('ParenBegin', "Function");
  WriteSymbol(''); # Just ParenBegin
  IgnoreWhitespace();
  while(!ParseAccept('ParenEnd'))
  { ParseExpect('Type', "Function argument");
    WriteSymbol(''); # Just type
    IgnoreWhitespace();
    ParseExpect('Name', "Function argument");
    WriteSymbol(' '); # space + name
    my $symbol = ParseExpect('Comma', 'ParenEnd', "more function arguments?");
    if($symbol->{template} eq 'Comma')
    { IgnoreWhitespace();
      WriteSymbol(''); # Just comma
      WriteSymbol(' '); # Just space
    } else
    { $symbolIndex--; # Roll back lookahead to re-test ParenEnd in while loop
    }
  }
  WriteSymbol(''); # Just ParenEnd
  IgnoreWhitespace();
  ParseExpect('BlockBegin', "Function block");
  WriteSymbol("\n" . RenderIndent()); # newline + indent + {
  $indent++;
  while(!ParseAccept('BlockEnd'))
  { ParseStatement();
    ParseStatementEnd();
  }
  $indent--;
  WriteSymbol("\n" . RenderIndent()); # newline + }
  WriteSymbol("\n\n"); # Blank line
}

sub ParseState
{ $symbolIndex = 0; # Forget lookahead
  # $indent must equal 0, so I'm never trying to render it here.
  ParseExpect('State', "New State");
}

sub RenderIndent
{ return("  " x $indent);
}

sub puts
{ print "$_[0]\n";
}

sub WriteSymbol
{ my $whitespace = shift;
  die("WriteSymbol called while \$symbolIndex = $symbolIndex, instead of 0 or 1 as required.")
    unless($symbolIndex<2);
  if(defined $symbols)
  { print $whitespace . $symbols->[0]{content};
    splice @$symbols, 0, $symbolIndex; # Discard topmost symbols up to and excluding $symbolIndex.
  }
  $symbolIndex = 0;
}

sub ReadSymbol
{ while(!defined($symbols->[$symbolIndex]))
  {
# print Dumper
# ( { label => "Before read"
#   , where => "($inputRow, $inputColumn)"
#   , remaining => $inputLine
#   , symbols => $symbols
#   , symbolIndex => $symbolIndex
#   }
# ) if $breakflag;

    if(!defined $inputLine || $inputLine eq '') # Blank at symbol read means end of line reached.
    { $inputRow++;
      $inputColumn = 0;
      $inputLine = <> || die "Reading from STDIN failed at line $inputRow: $!";
      return({ 'template' => 'EOF', symbolContent => '' })
        unless($inputLine); # Blank right after a file read means end of file reached.
    }
    my $symbol =
      FALSE;

    for my $template (@$lexemeOrder)
    { if($inputLine =~ s/^(?<symbolContent>$lexemeTemplates->{$template})//)
      { $symbol =
        { template => $template
        , content => $+{symbolContent}
        };
        push @$symbols, $symbol;
        $inputColumn += length $+{symbolContent};
        last;
      }
      # if($template eq 'NumberLiteral') {die($lexemeTemplates->{$template});}
    }
    die
    ( "Unkown input found at "
    . "input ($inputRow, $inputColumn) during \"ReadSymbol\"."
    . "\nRemaining line was"
    . ":\n$inputLine"
    ) unless $symbol;

    
# print Dumper
# ( { label => "After read"
#   , where => "($inputRow, $inputColumn)"
#   , remaining => $inputLine
#   , symbols => $symbols
#   , symbolIndex => $symbolIndex
#   }
# ) if $breakflag;
  }
# die if $breakflag;
  return $symbols->[$symbolIndex];
}

sub TestTemplates
{ my $testTemplates = shift;
  my $functionName = shift;
  my $lambda = shift;
  $testTemplates = [$testTemplates] if(ref($testTemplates) eq '');
  die("Bad test templates passed to $functionName: ". Dumper($testTemplates))
    unless(ref($testTemplates) eq 'ARRAY');
  foreach my $testTemplate (@$testTemplates)
  { my $ret = $lambda->($testTemplate);
    # Allow lambda to short circuit other checks by returning singleton array
    return($ret->[0]) if(ref($ret) eq 'ARRAY');
  }
  return(FALSE);
}


sub ParseAccept
{ my $testTemplates = shift;
# puts("EHABA");
  return TestTemplates
    ( $testTemplates
    , 'ParseAccept'
    , sub
      { 
# puts("EHABB");
        my $symbol = ReadSymbol($testTemplates);
# puts("EHABC");
        my $template = shift;
        if($symbol->{template} eq $template )
        { $symbolIndex++;
          # die(Dumper($symbol));
# puts("EHABD");
          return([$symbol]);
        }
# puts("EHABE");
      }
    );
}

sub ParseExpect
{ my $testTemplates = shift;
  my $label = shift;
  my $found = TestTemplates
    ( $testTemplates
    , 'ParseExpect'
    , sub
      { my $symbol = ParseAccept(shift);
        if($symbol)
        { return [$symbol];
        }
      }
    )
    || FALSE
    ;

  if($found)
  { return($found);
  }
  my $symbol = ReadSymbol($testTemplates);
  die
  ( "Unexpected $symbol->{template} Symbol '$symbol->{content}' found at "
  . "input ($inputRow, $inputColumn) during \"$label\"."
  . " We were instead expecting one of: "
  . Dumper($testTemplates)
  . "\nRemaining line was"
  . ":\n$inputLine"
  );
}

sub ParseIgnore
{ $symbolIndex = $symbolIndex || 0;
# puts("EHAA");
  TestTemplates
  ( shift
  , 'ParseIgnore'
  , sub
    { my $testTemplate = shift;
# puts("EHAB");
      if(ParseAccept($testTemplate))
      { 
# puts("EHAC");
        if($symbolIndex == 1)
        { shift @$symbols;
          $symbolIndex = 0;
        }
        return ParseIgnore($testTemplate);
      }
    }
  )
}

sub IgnoreWhitespace
{ 
# puts("EHA");
  ParseIgnore(['Whitespace']);
# puts("EHB");
}

ParseProgram();
