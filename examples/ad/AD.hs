{-# LANGUAGE DataKinds, GADTs, TypeFamilies, TypeOperators #-}
{-# LANGUAGE LambdaCase                                    #-}
{-# LANGUAGE MultiParamTypeClasses                         #-}
{-# LANGUAGE ScopedTypeVariables                           #-}
{-# OPTIONS_GHC -Wno-type-defaults -Wno-unused-imports -Wno-missing-signatures -Wno-unused-matches #-}

module Main where

import Torch.Core.Tensor.Static.Double
import Torch.Core.Tensor.Static.DoubleMath
import Torch.Core.Tensor.Static.DoubleRandom

import Data.Singletons
import Data.Singletons.Prelude
import Data.Singletons.TypeLits

type SN = StaticNetwork
type SW = StaticWeights

data StaticWeights (i :: Nat) (o :: Nat) = SW {
  biases :: TDS '[o],
  weights :: TDS '[o, i]
  } deriving (Show)

data Sigmoid (i :: Nat) =
  Sigmoid deriving Show

data Relu (i :: Nat) =
  Relu deriving Show

data Trivial (i :: Nat) =
  Trivial deriving Show

data Layer (i :: Nat) (o :: Nat) where
  TrivialLayer :: Trivial i -> Layer i i
  -- LinearLayer  :: SW i o    -> Layer i o
  LinearLayer  :: TDS '[o, i] -> Layer i o
  SigmoidLayer :: Sigmoid i -> Layer i i
  ReluLayer :: Relu i -> Layer i i

type UpdateFunction i o = Layer i o -> Layer i o

type Sensitivity i = TDS '[i]
type Gradient d = TDS d

fstLayer :: forall i h hs o . SN i (h : hs) o -> Layer i h
fstLayer (f :~ r) = f

rstLayers :: forall i h hs o . SN i (h : hs) o -> SN h hs o
rstLayers (f :~ r) = r

data Table :: Nat -> [Nat] -> Nat -> * where
  V :: (KnownNat i, KnownNat o) =>
       (Gradient d, Sensitivity i) -> Table i '[] o
  (:&~) :: (KnownNat h, KnownNat i, KnownNat o, SingI d) =>
          (Gradient d, Sensitivity i) -> Table h hs o -> Table i (h ': hs) o

updateTensor :: SingI d => TDS d -> TDS d -> Double -> TDS d
updateTensor t dEdt learningRate = t ^+^ (learningRate *^ dEdt)

updateMatrix :: (KnownNat o, KnownNat i, d ~ [o, i]) =>
  TDS d -> Gradient d -> Double -> TDS [o, i]
updateMatrix t dEdt learningRate = t ^+^ (learningRate *^ dEdt)

class State s g where
  update :: Layer i o -> s -> Layer i o

instance State (Layer i o) (TDS d) where
  update layer grad = undefined

-- instance State Layer where
--   -- update (TrivialLayer l) _ _ = TrivialLayer l
--   -- update _ _ _ = undefined

class Propagate l where
  forwardProp :: forall i o . (KnownNat i, KnownNat o) =>
    TDS '[i] -> (l i o) -> TDS '[o]
  backProp :: forall i o d . (KnownNat i, KnownNat o, SingI d) =>
    Sensitivity o -> (l i o) -> (Gradient d, Sensitivity i)
  -- update :: forall d i o . SingI d => l i o -> Gradient d -> Double -> l i o
  -- ISSUE: need to specialize d to more specific types that are dependent on the layer type

instance Propagate Layer where
  forwardProp t (TrivialLayer l) = t
  forwardProp t (LinearLayer w :: Layer i o) =
    tds_resize ( w !*! t')
    where
      t' = (tds_resize t :: TDS '[i, 1])
  -- forwardProp t (LinearLayer (SW b w) :: Layer i o) =
  --   tds_resize ( w !*! t' + b')
  --   where
  --     t' = (tds_resize t :: TDS '[i, 1])
  --     b' = tds_resize b
  forwardProp t (SigmoidLayer l) = tds_sigmoid t
  forwardProp t (ReluLayer l) = (tds_gtTensorT t (tds_new)) ^*^ t
  backProp dEds layer = (tds_new, tds_new)
  -- update (TrivialLayer l) _ _ = TrivialLayer l
  -- update (LinearLayer w :: Layer i o) gradient learningRate =
  --   (LinearLayer (updateTensor w gradient learningRate) :: Layer i o)
    -- ISSUE: need to specialize d to [i, o] in this case
  -- update _ _ _ = undefined      -- 

trivial' :: SingI d => TDS d -> TDS d
trivial' t = tds_init 1.0

sigmoid' :: SingI d => TDS d -> TDS d
sigmoid' t = (tds_sigmoid t) ^*^ ((tds_init 1.0) ^-^ tds_sigmoid t)

relu' :: SingI d => TDS d -> TDS d
relu' t = (tds_gtTensorT t (tds_new))

forwardNetwork :: forall i h o . TDS '[i] -> SN i h o  -> TDS '[o]
forwardNetwork t (O w) = forwardProp t w
forwardNetwork t (h :~ n) = forwardNetwork (forwardProp t h) n

mkW :: (SingI i, SingI o) => SW i o
mkW = SW b n
  where (b, n) = (tds_new, tds_new)

sigmoid :: forall d . (SingI d) => Layer d d
sigmoid = SigmoidLayer (Sigmoid :: Sigmoid d)

relu :: forall d . (SingI d) => Layer d d
relu = ReluLayer (Relu :: Relu d)

linear  :: forall i o . (SingI i, SingI o) => Layer i o
-- linear = LinearLayer (mkW :: SW i o)
linear = LinearLayer tds_new

data StaticNetwork :: Nat -> [Nat] -> Nat -> * where
  O :: (KnownNat i, KnownNat o) =>
       Layer i o -> SN i '[] o
  (:~) :: (KnownNat h, KnownNat i, KnownNat o) =>
          Layer i h -> SN h hs o -> SN i (h ': hs) o

-- set precedence to chain layers without adding parentheses
infixr 5 :~

instance (KnownNat i, KnownNat o) => Show (Layer i o) where
  show (TrivialLayer x) = "TrivialLayer "
                         ++ (show (natVal (Proxy :: Proxy i))) ++ " "
                         ++ (show (natVal (Proxy :: Proxy o)))
  show (LinearLayer x) = "LinearLayer "
                         ++ (show (natVal (Proxy :: Proxy i))) ++ " "
                         ++ (show (natVal (Proxy :: Proxy o)))
  show (SigmoidLayer x) = "SigmoidLayer "
                         ++ (show (natVal (Proxy :: Proxy i))) ++ " "
                         ++ (show (natVal (Proxy :: Proxy o)))
  show (ReluLayer x) = "ReluLayer "
                         ++ (show (natVal (Proxy :: Proxy i))) ++ " "
                         ++ (show (natVal (Proxy :: Proxy o)))

dispL :: forall o i . (KnownNat o, KnownNat i) => Layer i o -> IO ()
dispL layer = do
    let inVal = natVal (Proxy :: Proxy i)
    let outVal = natVal (Proxy :: Proxy o)
    print layer
    print $ "inputs: " ++ (show inVal) ++ "    outputs: " ++ show (outVal)

dispN :: SN h hs c -> IO ()
dispN (O w) = dispL w
dispN (w :~ n') = putStrLn "\nCurrent Layer ::::" >> dispL w >> dispN n'

li :: Layer 10 7
li = linear
l2 :: Layer 7 7
l2 = sigmoid
l3 :: Layer 7 4
l3 = linear
l4 :: Layer 4 4
l4 = sigmoid
lo :: Layer 4 2
lo = linear

net = li :~ l2 :~ l3 :~ l4 :~ O lo

main :: IO ()
main = do

  gen <- newRNG
  t <- tds_normal gen 0.0 5.0 :: IO (TDS '[10])
  tds_p $ tds_gtTensorT t tds_new

  print s
  dispN net
  tds_p $ forwardNetwork (tds_init 5.0) net

  putStrLn "Done"
  where
    s = Sigmoid :: Sigmoid (3 :: Nat)