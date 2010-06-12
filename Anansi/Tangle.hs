-- Copyright (C) 2010 John Millikin <jmillikin@gmail.com>
-- 
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- any later version.
-- 
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
-- 
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.
-- 
{-# LANGUAGE OverloadedStrings #-}
module Anansi.Tangle (tangle) where
import Control.Monad.Trans.Class (lift)
import qualified Control.Monad.Trans.State as S
import qualified Data.Text.Lazy as TL
import qualified Data.Map as Map
import Anansi.Types

type ContentMap = Map.Map TL.Text [Content]

data TangleState = TangleState TL.Text ContentMap
type TangleT m a = S.StateT TangleState m a

buildMacros :: [Block] -> ContentMap
buildMacros blocks = S.execState (mapM_ accumMacro blocks) Map.empty

accumMacro :: Block -> S.State ContentMap ()
accumMacro b = case b of
	BlockText _ -> return ()
	BlockFile _ _ -> return ()
	BlockDefine name content -> do
		macros <- S.get
		S.put $ Map.insertWith (\new old -> old ++ new) name content macros

buildFiles :: [Block] -> ContentMap
buildFiles blocks = S.execState (mapM_ accumFile blocks) Map.empty

accumFile :: Block -> S.State ContentMap ()
accumFile b = case b of
	BlockText _ -> return ()
	BlockDefine _ _ -> return ()
	BlockFile name content -> do
		let accum new old = old ++ new ++ [ContentText "\n"]
		files <- S.get
		S.put $ Map.insertWith accum name content files

tangle :: Monad m => (TL.Text -> ((TL.Text -> m ()) -> m TangleState) -> m TangleState) -> [Block] -> m ()
tangle open blocks = S.evalStateT (mapM_ putFile files) (TangleState "" macros) where
	fileMap = buildFiles blocks
	macros = buildMacros blocks
	files = Map.toAscList fileMap
	
	putFile (path, content) = do
		state <- S.get
		newState <- lift $ open path $ \w -> S.execStateT (mapM_ (putContent w) content) state
		S.put newState

putContent :: Monad m => (TL.Text -> m ()) -> Content -> TangleT m ()
putContent w (ContentText t) = do
	TangleState indent _ <- S.get
	lift $ do
		w indent
		w t
		w "\n"

putContent w (ContentMacro indent name) = addIndent putMacro where
	addIndent m = do
		TangleState old macros <- S.get
		S.put $ TangleState (TL.append old indent) macros
		m
		S.put $ TangleState old macros
	putMacro = lookupMacro name >>= mapM_ (putContent w)

lookupMacro :: Monad m => TL.Text -> TangleT m [Content]
lookupMacro name = do
	TangleState _ macros <- S.get
	case Map.lookup name macros of
		Nothing -> error $ "unknown macro: " ++ show name
		Just content -> return content