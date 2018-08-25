module GameState.PlayingLevel.Failed.FailedAnimation
    exposing
        ( Model
        , Action(..)
        , init
        , updateTick
        , view
        )

import Data.Config exposing (Config)
import Data.Direction as Direction exposing (Direction)
import Actor.Actor as Actor
import Actor.Common as Common
import Dict
import LevelInitializer
import InputController
import Renderer.Svg.LevelRenderer as LevelRenderer
import Html exposing (Html)
import Actor.EventManager as EventManager
import GameState.PlayingLevel.Animation.Animation as Animation
import Actor.LevelUpdate as LevelUpdate


type alias Model =
    { config : Config
    , levelConfig : Actor.LevelConfig
    , level : Actor.Level
    , animationModel : Animation.Model
    , description : String
    }


type Action
    = Stay Model
    | Finished String


init : Config -> Actor.LevelConfig -> Animation.Model -> String -> Actor.Level -> Model
init config levelConfig animationModel description level =
    { config = config
    , levelConfig = levelConfig
    , level = level
    , animationModel = animationModel
    , description = description
    }


updateTick : Int -> InputController.Model -> Model -> Action
updateTick currentTick inputModel model =
    case InputController.getOrderedPressedKeys inputModel |> List.head of
        Just InputController.StartKey ->
            Finished model.description

        _ ->
            case Animation.updateTick currentTick model.animationModel model.level of
                Animation.Stay animationModel level ->
                    model
                        |> flip setAnimation animationModel
                        |> flip setLevel level
                        |> (\model ->
                                LevelUpdate.update
                                    (InputController.getCurrentDirection inputModel)
                                    model.level
                                    model.levelConfig
                                    -- We won't handle events
                                    |> EventManager.clearEvents
                                    -- Prevents view movement
                                    |> Common.setView model.level.view
                                    |> setLevel model
                           )
                        |> Stay

                Animation.Finished ->
                    Finished model.description


setAnimation : Model -> Animation.Model -> Model
setAnimation model animationModel =
    { model | animationModel = animationModel }


setLevel : Model -> Actor.Level -> Model
setLevel model level =
    { model | level = level }


view : Int -> Model -> Html msg
view currentTick model =
    LevelRenderer.renderLevel currentTick model.config model.level model.levelConfig.images
