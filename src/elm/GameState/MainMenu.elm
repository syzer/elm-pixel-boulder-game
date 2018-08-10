module GameState.MainMenu
    exposing
        ( Model
        , Action(..)
        , init
        , updateTick
        , view
        )

import Text
import Data.Menu as Menu
import Data.Config exposing (Config)
import InputController
import Html exposing (Html, div)
import Renderer.Canvas.TextRenderer as TextRenderer
import List.Extra
import Maybe.Extra
import Color


type alias Model =
    { config : Config
    , menu : Menu.Menu
    , tick : Int
    , delay : Int
    }


type Action
    = Stay Model
    | LoadLevel String


init : Config -> Model
init config =
    { config = config
    , menu =
        { items =
            { before = []
            , selected =
                { key = "001"
                , text = Text.stringToLetters "Pixel"
                }
            , after =
                [ { key = "images"
                  , text = Text.stringToLetters "Images"
                  }
                , { key = "pacman"
                  , text = Text.stringToLetters "Pac-Man"
                  }
                , { key = "tank"
                  , text = Text.stringToLetters "Tank"
                  }
                ]
            }
        }
    , tick = 0
    , delay = 0
    }


updateTick : InputController.Model -> Model -> Action
updateTick inputModel model =
    if model.delay > 0 then
        model
            |> decreaseDelay
            |> Stay
    else
        case InputController.getOrderedPressedKeys inputModel |> List.head of
            Just InputController.UpKey ->
                Menu.moveMenuUp model.menu
                    |> setMenu model
                    |> resetTick
                    |> setDelay
                    |> Stay

            Just InputController.DownKey ->
                Menu.moveMenuDown model.menu
                    |> setMenu model
                    |> resetTick
                    |> setDelay
                    |> Stay

            Just InputController.SubmitKey ->
                LoadLevel model.menu.items.selected.key

            _ ->
                increaseTick model
                    |> Stay


increaseTick : Model -> Model
increaseTick model =
    { model | tick = model.tick + 1 }


resetTick : Model -> Model
resetTick model =
    { model | tick = 0 }


decreaseDelay : Model -> Model
decreaseDelay model =
    { model | delay = model.delay - 1 }


setDelay : Model -> Model
setDelay model =
    { model | delay = 4 }


view : Model -> Html msg
view model =
    TextRenderer.renderText
        model.config.width
        model.config.height
        (Maybe.Extra.values
            [ List.Extra.last model.menu.items.before |> Maybe.map (\item -> ( 0, -3, Color.red, item.text ))
            , Just ( getXOffset model model.menu.items.selected.text, 3, Color.blue, model.menu.items.selected.text )
            , List.head model.menu.items.after |> Maybe.map (\item -> ( 0, 9, Color.red, item.text ))
            ]
        )


getXOffset : Model -> Text.Letters -> Int
getXOffset model letters =
    let
        lineLength =
            getLineLength letters

        beforeLength =
            3

        afterLength =
            1

        totalLength =
            beforeLength + lineLength + afterLength

        minOffset =
            0

        maxOffset =
            max 0 (lineLength - model.config.width)

        tickSpeedCorrection =
            model.tick // 4

        offset =
            (tickSpeedCorrection % totalLength) - beforeLength
    in
        clamp minOffset maxOffset offset
            |> negate


getLineLength : Text.Letters -> Int
getLineLength letters =
    letters
        |> List.map .width
        |> List.sum
        |> (+) (List.length letters)


setMenu : Model -> Menu.Menu -> Model
setMenu model menu =
    { model | menu = menu }
