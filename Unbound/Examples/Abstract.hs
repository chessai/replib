{-# LANGUAGE TemplateHaskell, UndecidableInstances, ExistentialQuantification,
    TypeOperators, GADTs, TypeSynonymInstances, FlexibleInstances,
    ScopedTypeVariables, MultiParamTypeClasses, StandaloneDeriving
 #-}
-----------------------------------------------------------------------------
-- |
-- Module      :  LC
-- Copyright   :  (c) The University of Pennsylvania, 2010
-- License     :  BSD
--
-- Maintainer  :  sweirich@cis.upenn.edu
-- Stability   :  experimental
-- Portability :  non-portable
--
--
--
-----------------------------------------------------------------------------

-- | This example demonstrates how to use abstract types as part of
-- the syntax of the untyped lambda calculus
--
-- Suppose we wish to include Source positions in our Abstract Syntax
--
module Examples.Abstract where

import Generics.RepLib
import Unbound.LocallyNameless

import qualified Data.Set as S


-- We import the type SourcePos, but it is an abstract data type
-- all we know about it is that it is an instance of the Eq, Show and Ord classes.
import Text.ParserCombinators.Parsec.Pos (SourcePos, newPos)

-- Since we don't know the structure of the type, we create an "abstract"
-- representation for it. This defines rSourcePos :: R SourcePos and makes
-- SourcePos an instance of the Rep and Rep1 type classes.
--
-- Right now, this line triggers a warning because the TemplateHaskell code
-- does not work well with type abbreviations. The warning is safe to ignore.
$(derive_abstract [''SourcePos])

-- | A Simple datatype for the Lambda Calculus that includes source position
-- information
data Exp = Var SourcePos (Name Exp)
         | Lam (Bind (Name Exp) Exp)
         | App Exp Exp
  deriving Show

$(derive [''Exp])

-- To make Exp an instance of Alpha, we also need SourcePos to be an
-- instance of Alpha, because it appears inside the Exp type.  When we
-- do so, we override the default definition of aeq'.  There are a
-- few reasonable choices for this:
--
-- (1) match no source positions together  --- default definition
--      aeq' c s1 s2 = False
-- (2) match all source positions together
--      aeq' c s1 s2 = True
-- (3) only match equal source positions together
--      aeq' c s1 s2 = s1 == s2
--
--
-- Below, we choose option (2) because we would like
-- (alpha-)equivalence for Exp to ignore the source position
-- information. Two free variables with the same name but with
-- different source positions should be equal.
--
-- The other defaults for Alpha are fine.
instance Alpha SourcePos where
   aeq' c s1 s2 = True
   acompare' c s1 s2 = EQ

instance Alpha Exp where

instance Subst Exp SourcePos where
instance Subst Exp Exp where
   isvar (Var _ x) = Just (SubstName x)
   isvar _       = Nothing

type M a = LFreshM a

-- | Beta-Eta equivalence for lambda calculus terms.
(=~) :: Exp -> Exp -> M Bool
e1 =~ e2 | e1 `aeq` e2 = return True
e1 =~ e2 = do
    e1' <- red e1
    e2' <- red e2
    if e1' `aeq` e1 && e2' `aeq` e2
      then return False
      else e1' =~ e2'


-- | Parallel beta-eta reduction for lambda calculus terms.
-- Do as many reductions as possible in one step, while still ensuring
-- termination.
red :: Exp -> M Exp
red (App e1 e2) = do
  e1' <- red e1
  e2' <- red e2
  case e1' of
    -- look for a beta-reduction
    Lam bnd ->
      lunbind bnd $ \ (x, e1'') ->
        return $ subst x e2' e1''
    otherwise -> return $ App e1' e2'
red (Lam bnd) = lunbind bnd $ \ (x, e) -> do
   e' <- red e
   case e of
     -- look for an eta-reduction
     App e1 (Var _ y) | y `aeq` x && x `S.notMember` fv e1 -> return e1
     otherwise -> return (Lam (bind x e'))
red v = return $ v



---------------------------------------------------------------------
-- Some testing code to demonstrate this library in action.

assert :: String -> Bool -> IO ()
assert s True  = return ()
assert s False = print ("Assertion " ++ s ++ " failed")

assertM :: String -> M Bool -> IO ()
assertM s c =
  if (runLFreshM c) then return ()
  else print ("Assertion " ++ s ++ " failed")

x :: Name Exp
x = string2Name "x"

y :: Name Exp
y = string2Name "y"

z :: Name Exp
z = string2Name "z"

s :: Name Exp
s = string2Name "s"

sp = newPos "Foo" 1 2
sp2 = newPos "Bar" 3 4

lam :: Name Exp -> Exp -> Exp
lam x y = Lam (bind x y)

var :: Name Exp -> Exp
var n = Var sp n

zero  = lam s (lam z (var z))
one   = lam s (lam z (App (var s) (var z)))
two   = lam s (lam z (App (var s) (App (var s) (var z))))
three = lam s (lam z (App (var s) (App (var s) (App (var s) (var z)))))

plus = lam x (lam y (lam s (lam z (App (App (var x) (var s)) (App (App (var y) (var s)) (var z))))))

true = lam x (lam y (var x))
false = lam x (lam y (var y))
if_ x y z = (App (App x y) z)

main :: IO ()
main = do
  -- \x.x `aeq` \x.y, no matter what the source positions are
  assert "a1" $ lam x (var x) `aeq` lam y (Var sp2 y)
  -- \x.x /= \x.y
  assert "a2" $ not(lam x (var y) `aeq` lam x (var x))
  -- \x.(\y.x) (\y.y) `aeq` \y.y
  assertM "be1" $ lam x (App (lam y (var x)) (lam y (var y))) =~ (lam y (var y))
  -- \x. f x `aeq` f
  assertM "be2" $ lam x (App (var y) (var x)) =~ var y
  assertM "be3" $ if_ true (var x) (var y) =~ var x
  assertM "be4" $ if_ false (var x) (var y) =~ var y
  assertM "be5" $ App (App plus one) two =~ three

