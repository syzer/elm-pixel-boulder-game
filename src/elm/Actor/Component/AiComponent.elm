module Actor.Component.AiComponent exposing (updateAiComponent)

import Actor.Actor as Actor
    exposing
        ( Actor
        , AiComponentData
        , AiType(..)
        , Components
        , GameOfLifeAiAction
        , GameOfLifeAiData
        , Level
        )
import Actor.Common as Common
import Actor.Component.CollectibleComponent as CollectibleComponent
import Data.Position as Position exposing (Position)
import Dict
import Maybe.Extra
import Pilf exposing (flip)


updateAiComponent : AiComponentData -> Actor -> Actor.Entities -> Level -> Level -> Level
updateAiComponent aiData actor entities levelBeforeUpdate level =
    case aiData.ai of
        GameOfLifeAi gameOfLifeData ->
            updateGameOfLifeAi aiData gameOfLifeData actor entities levelBeforeUpdate level


updateGameOfLifeAi : AiComponentData -> GameOfLifeAiData -> Actor -> Actor.Entities -> Level -> Level -> Level
updateGameOfLifeAi aiData gameOfLifeData actor entities levelBeforeUpdate level =
    Common.getPosition actor
        |> Maybe.map (getSearchTagCount levelBeforeUpdate gameOfLifeData.tagToSearch)
        |> Maybe.andThen (findBecome gameOfLifeData.actions)
        |> Maybe.andThen (flip Dict.get entities)
        |> Maybe.map (doBecome actor)
        |> Maybe.map (Common.updateActor level.actors)
        |> Maybe.map (Common.updateActors level)
        |> Maybe.withDefault level


getSearchTagCount : Level -> String -> Position -> Int
getSearchTagCount levelBeforeUpdate tagName myPosition =
    Position.aroundNeighborOffsets
        |> List.map (Position.addPosition myPosition)
        |> List.concatMap (flip Common.getActorsByPosition levelBeforeUpdate)
        |> List.map Common.getTagComponent
        |> Maybe.Extra.values
        |> List.map .name
        |> List.filter ((==) tagName)
        |> List.length


findBecome : List GameOfLifeAiAction -> Int -> Maybe String
findBecome actions count =
    actions
        |> List.filter (\action -> action.count == count)
        |> List.head
        |> Maybe.map .become


doBecome : Actor -> Actor.Components -> Actor
doBecome actor newComponents =
    Dict.union newComponents actor.components
        |> Common.updateComponents actor