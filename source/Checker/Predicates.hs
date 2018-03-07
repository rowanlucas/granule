{-# LANGUAGE GADTs #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE DeriveGeneric #-}

module Checker.Predicates where

{-

This module provides the representation of theorems (predicates)
inside the type checker.

-}

import Data.List (intercalate)
import GHC.Generics (Generic)

import Context
import Syntax.FirstParameter
import Syntax.Pretty
import Syntax.Expr

data Quantifier =
    -- | Universally quantification, e.g. polymorphic
    ForallQ

    -- | Instantiations of universally quantified variables
    | InstanceQ

    -- | Univeral, but bound in a dependent pattern match
    | BoundQ
  deriving (Show, Eq)

instance Pretty Quantifier where
  pretty ForallQ   = "forall"
  pretty InstanceQ = "exists"
  pretty BoundQ    = "pi"

stripQuantifiers :: Ctxt (a, Quantifier) -> Ctxt a
stripQuantifiers = map (\(var, (k, _)) -> (var, k))


-- Represent constraints generated by the type checking algorithm
data Constraint =
    Eq  Span Coeffect Coeffect CKind
  | Neq Span Coeffect Coeffect CKind
  | ApproximatedBy Span Coeffect Coeffect CKind
  deriving (Show, Eq, Generic)

instance FirstParameter Constraint Span

-- Used to negate constraints
data Neg a = Neg a
  deriving Show

instance Pretty (Neg Constraint) where
    pretty (Neg (Neq _ c1 c2 _)) =
      "Trying to prove that " ++ pretty c1 ++ " /= " ++ pretty c2

    pretty (Neg (Eq _ c1 c2 _)) =
      pretty c1 ++ " /= " ++ pretty c2

    pretty (Neg (ApproximatedBy _ c1 c2 (CConstr k))) =
      case internalName k of
        "Nat=" -> pretty c1 ++ " /= " ++ pretty c2
        _ -> pretty c1 ++ " > " ++ pretty c2

instance Pretty [Constraint] where
    pretty constr =
      "---\n" ++ (intercalate "\n" . map pretty $ constr)

instance Pretty Constraint where
    pretty (Eq _ c1 c2 _) =
      "(" ++ pretty c1 ++ " == " ++ pretty c2 ++ ")" -- @" ++ show s

    pretty (Neq _ c1 c2 _) =
        "(" ++ pretty c1 ++ " /= " ++ pretty c2 ++ ")" -- @" ++ show s

    pretty (ApproximatedBy _ c1 c2 _) =
      "(" ++ pretty c1 ++ " <= " ++ pretty c2 ++ ")" -- @" ++ show s

-- Represents a predicate generated by the type checking algorithm
data Pred where
    Conj :: [Pred] -> Pred
    Impl :: [Id] -> Pred -> Pred -> Pred
    Con  :: Constraint -> Pred

deriving instance Show Pred
deriving instance Eq Pred

-- Fold operation on a predicate
predFold :: ([a] -> a) -> ([Id] -> a -> a -> a) -> (Constraint -> a) -> Pred -> a
predFold c i a (Conj ps)   = c (map (predFold c i a) ps)
predFold c i a (Impl eVar p p') = i eVar (predFold c i a p) (predFold c i a p')
predFold _ _ a (Con cons)  = a cons

instance Pretty Pred where
  pretty =
    predFold
     (intercalate " & ")
     (\s p q ->
         (if null s then "" else "forall " ++ intercalate "," (map sourceName s) ++ " . ")
      ++ "(" ++ p ++ " -> " ++ q ++ ")") pretty
