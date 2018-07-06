module Main exposing (main)

import Html exposing (Html, text, br, div)
import Keyboard
import Time
import Dict exposing (Dict)
import Dict.Extra
import Maybe.Extra
import Color exposing (Color)
import Canvas
import Canvas.Point


movingTime : Time.Time
movingTime =
    300 * Time.millisecond


pixelSize : Int
pixelSize =
    20


type alias Model =
    { level : Level
    , width : Int
    , height : Int
    , keys : Keys
    }


main : Program Never Model Msg
main =
    Html.program
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }


type Msg
    = NoOp
    | KeyPressed Keyboard.KeyCode
    | KeyDown Keyboard.KeyCode
    | KeyUp Keyboard.KeyCode
    | GameTick Time.Time


type alias Keys =
    { left : KeyStatus
    , right : KeyStatus
    , up : KeyStatus
    , down : KeyStatus
    }


type KeyStatus
    = NotPressed
    | WasPressed
    | IsPressed


type alias Actor =
    { id : Int
    , components : Dict String Component
    }


type alias TransformComponentData =
    { x : Int
    , y : Int
    , movingState : MovingState
    }


type alias CurrentPositionRenderComponentData =
    { color : Color
    }


type alias AdditionalPositionsRenderComponentData =
    { positions : List RenderablePosition
    }


type alias RenderablePosition =
    { xOffset : Int
    , yOffset : Int
    , color : Color
    }


type alias Position =
    { x : Int
    , y : Int
    }


type alias MovingTowardsData =
    { x : Int
    , y : Int
    , startTime : Time.Time
    , endTime : Time.Time
    , completionPercentage : Float
    }


type MovingState
    = NotMoving
    | MovingTowards MovingTowardsData


type Shape
    = Circle
    | Square


type Direction
    = Left
    | Up
    | Right
    | Down


type alias PhysicsComponentData =
    { mass : Int
    , shape : Shape
    , affectedByGravity : Bool
    }


type Component
    = TransformComponent TransformComponentData
    | CurrentPositionRenderComponent CurrentPositionRenderComponentData
    | AdditionalPositionRenderComponent AdditionalPositionsRenderComponentData
    | PlayerInputComponent
    | DiamondCollectorComponent
    | DiamondComponent
    | SquashableComponent
    | CanSquashComponent
    | PhysicsComponent PhysicsComponentData
    | RigidComponent


type alias Level =
    { actors : Dict Int Actor
    , nextActorId : Int
    , diamonds :
        { total : Int
        , collected : Int
        }
    }


init : ( Model, Cmd Msg )
init =
    let
        level =
            { actors = Dict.fromList []
            , nextActorId = 1
            , diamonds =
                { total = 0
                , collected = 0
                }
            }
                |> addPlayer 4 4
                |> addDirt 6 4
                |> addDirt 7 4
                |> addDirt 8 4
                |> addDirt 9 4
                |> addRock 7 1
                |> addDiamond 8 1
                |> addWall 4 11
                |> addWall 5 11
                |> addWall 6 11
                |> addWall 7 11
                |> addWall 8 11
    in
        { level = level
        , width = 12
        , height = 12
        , keys =
            { left = NotPressed
            , right = NotPressed
            , up = NotPressed
            , down = NotPressed
            }
        }
            ! []


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        KeyPressed keyCode ->
            (updateKeyState model IsPressed keyCode) ! []

        KeyDown keyCode ->
            (updateKeyState model IsPressed keyCode) ! []

        KeyUp keyCode ->
            (updateKeyState model WasPressed keyCode) ! []

        GameTick time ->
            let
                level =
                    model.level

                actors =
                    level.actors

                keys =
                    model.keys

                maybeInputForce =
                    calculateInputForce keys

                newLevel =
                    List.foldr
                        (\( actorId, actor ) level ->
                            let
                                ( _, updatedLevel ) =
                                    List.foldr
                                        (\( key, component ) ( actor, level ) ->
                                            let
                                                updatedLevel =
                                                    case component of
                                                        PlayerInputComponent ->
                                                            maybeInputForce
                                                                |> Maybe.andThen (\direction -> applyForce time level actor direction)
                                                                |> Maybe.withDefault level

                                                        TransformComponent transformData ->
                                                            case transformData.movingState of
                                                                MovingTowards movingData ->
                                                                    handleMovingTowards time transformData movingData actor
                                                                        |> updateActor level actor.id

                                                                _ ->
                                                                    level

                                                        DiamondCollectorComponent ->
                                                            tryToCollectDiamond level actor

                                                        CanSquashComponent ->
                                                            trySquashingThings level actor

                                                        PhysicsComponent physics ->
                                                            tryApplyPhysics time level actor physics

                                                        _ ->
                                                            level
                                            in
                                                ( actor, updatedLevel )
                                        )
                                        ( actor, level )
                                        (Dict.toList actor.components)
                            in
                                updatedLevel
                        )
                        level
                        (Dict.toList actors)

                handlePressedKey keyStatus =
                    case keyStatus of
                        WasPressed ->
                            NotPressed

                        other ->
                            other

                handledPressedKeys =
                    { left = handlePressedKey keys.left
                    , right = handlePressedKey keys.right
                    , up = handlePressedKey keys.up
                    , down = handlePressedKey keys.down
                    }
            in
                { model
                    | keys = handledPressedKeys
                    , level = newLevel
                }
                    ! []

        NoOp ->
            model ! []


applyForce : Time.Time -> Level -> Actor -> Direction -> Maybe Level
applyForce time level actor direction =
    getTransformComponent actor.components
        |> Maybe.andThen
            -- Can only apply force if not already moving
            (\transformData ->
                case transformData.movingState of
                    NotMoving ->
                        Just transformData

                    _ ->
                        Nothing
            )
        |> Maybe.andThen
            -- Can only move if that spot is not already taken
            (\transformData ->
                let
                    offset =
                        getOffsetFromForce direction

                    newPosition =
                        addPositions { x = transformData.x, y = transformData.y } offset
                in
                    case getActorWhoClaimed level.actors newPosition of
                        Nothing ->
                            Just ( transformData, offset, newPosition )

                        Just actor ->
                            if hasRigidComponent actor.components then
                                Nothing
                                -- @todo add a branch in case can push the component in that spot
                            else
                                Just ( transformData, offset, newPosition )
            )
        |> Maybe.andThen
            (\( transformData, offset, newPosition ) ->
                Just (handleMovement time level actor transformData offset newPosition)
            )


handleMovement : Time.Time -> Level -> Actor -> TransformComponentData -> Position -> Position -> Level
handleMovement time level actor transformData offset newPosition =
    let
        newComponents =
            Dict.insert
                "transform"
                (TransformComponent
                    { transformData
                        | movingState =
                            MovingTowards
                                { x = newPosition.x
                                , y = newPosition.y
                                , startTime = time
                                , endTime = time + movingTime
                                , completionPercentage = 0.0
                                }
                    }
                )
                actor.components
                |> Dict.insert
                    "additional-render"
                    (AdditionalPositionRenderComponent
                        { positions =
                            [ { xOffset = offset.x
                              , yOffset = offset.y
                              , color =
                                    getCurrentPositionRenderComponent actor.components
                                        |> Maybe.andThen
                                            (\renderData ->
                                                Just renderData.color
                                            )
                                        |> Maybe.withDefault Color.white
                              }
                            ]
                        }
                    )

        newActors =
            Dict.insert
                actor.id
                { actor | components = newComponents }
                level.actors
    in
        { level | actors = newActors }


hasRigidComponent : Dict String Component -> Bool
hasRigidComponent =
    Dict.member "rigid"


getActorWhoClaimed : Dict Int Actor -> Position -> Maybe Actor
getActorWhoClaimed actors position =
    Dict.Extra.find
        (\actorId actor ->
            getTransformComponent actor.components
                |> Maybe.andThen
                    (\transformData ->
                        if transformData.x == position.x && transformData.y == position.y then
                            Just actor
                        else
                            Nothing
                    )
                |> Maybe.Extra.isJust
        )
        actors
        |> Maybe.andThen
            (\( actorId, actor ) ->
                Just actor
            )


getOffsetFromForce : Direction -> Position
getOffsetFromForce direction =
    case direction of
        Left ->
            { x = -1, y = 0 }

        Up ->
            { x = 0, y = -1 }

        Right ->
            { x = 1, y = 0 }

        Down ->
            { x = 0, y = 1 }


addPositions : Position -> Position -> Position
addPositions pos1 pos2 =
    { x = pos1.x + pos2.x
    , y = pos1.y + pos2.y
    }


calculateInputForce : Keys -> Maybe Direction
calculateInputForce keys =
    if isMoving keys.left then
        Just Left
    else if isMoving keys.up then
        Just Up
    else if isMoving keys.right then
        Just Right
    else if isMoving keys.down then
        Just Down
    else
        Nothing


tryApplyPhysics : Time.Time -> Level -> Actor -> PhysicsComponentData -> Level
tryApplyPhysics time level actor physics =
    if physics.affectedByGravity then
        getTransformComponent actor.components
            |> Maybe.andThen
                (\transformData ->
                    case transformData.movingState of
                        NotMoving ->
                            Just transformData

                        _ ->
                            -- Can not update physics when already moving
                            Nothing
                )
            |> Maybe.andThen
                (\transformData ->
                    -- Get the actor below us
                    let
                        offset =
                            getOffsetFromForce Down

                        belowPosition =
                            addPositions { x = transformData.x, y = transformData.y } offset
                    in
                        case getActorWhoClaimed level.actors belowPosition of
                            Nothing ->
                                -- Do movement
                                Just ( transformData, offset, belowPosition )

                            -- @todo be able to rollover if below is a circle
                            _ ->
                                Nothing
                )
            |> Maybe.andThen
                (\( transformData, offset, newPosition ) ->
                    Just (handleMovement time level actor transformData offset newPosition)
                )
            |> Maybe.withDefault level
    else
        level


tryToCollectDiamond : Level -> Actor -> Level
tryToCollectDiamond level focusedActor =
    case getTransformComponent focusedActor.components of
        Just focusedTransformData ->
            Dict.foldr
                (\actorId actor level ->
                    if Dict.member "diamond" actor.components then
                        case getTransformComponent actor.components of
                            Just diamondTransformData ->
                                if diamondTransformData == focusedTransformData then
                                    let
                                        newActors =
                                            Dict.remove actorId level.actors

                                        diamonds =
                                            level.diamonds

                                        newDiamonds =
                                            { diamonds | collected = diamonds.collected + 1 }
                                    in
                                        { level
                                            | actors = newActors
                                            , diamonds = newDiamonds
                                        }
                                else
                                    level

                            _ ->
                                level
                    else
                        level
                )
                level
                level.actors

        Nothing ->
            level


trySquashingThings : Level -> Actor -> Level
trySquashingThings level focusedActor =
    case getTransformComponent focusedActor.components of
        Just focusedTransformData ->
            Dict.foldr
                (\actorId actor level ->
                    if Dict.member "squashable" actor.components then
                        case getTransformComponent actor.components of
                            Just squashableTransformData ->
                                if squashableTransformData == focusedTransformData then
                                    let
                                        newActors =
                                            Dict.remove actorId level.actors
                                    in
                                        { level | actors = newActors }
                                else
                                    level

                            _ ->
                                level
                    else
                        level
                )
                level
                level.actors

        Nothing ->
            level


updateActor : Level -> Int -> Actor -> Level
updateActor level actorId actor =
    let
        newActors =
            Dict.insert
                actorId
                actor
                level.actors
    in
        { level | actors = newActors }


handleMovingTowards : Time.Time -> TransformComponentData -> MovingTowardsData -> Actor -> Actor
handleMovingTowards currentTime transformData towardsData actor =
    if currentTime > towardsData.endTime then
        let
            newComponents =
                Dict.insert
                    "transform"
                    (TransformComponent
                        { x = towardsData.x
                        , y = towardsData.y
                        , movingState = NotMoving
                        }
                    )
                    actor.components
                    |> Dict.remove "additional-render"
        in
            { actor | components = newComponents }
    else
        let
            newComponents =
                Dict.insert
                    "transform"
                    (TransformComponent
                        { transformData
                            | movingState =
                                MovingTowards
                                    { towardsData
                                        | completionPercentage = calculateCompletionPercentage towardsData.startTime towardsData.endTime currentTime
                                    }
                        }
                    )
                    actor.components
        in
            { actor | components = newComponents }


calculateCompletionPercentage : Time.Time -> Time.Time -> Time.Time -> Float
calculateCompletionPercentage startTime endTime currentTime =
    100 / (endTime - startTime) * (currentTime - startTime)


isMoving : KeyStatus -> Bool
isMoving status =
    case status of
        NotPressed ->
            False

        _ ->
            True



{-
   view : Model -> Html Msg
   view model =
       div
           []
           (List.range 0 (model.height - 1)
               |> List.map
                   (\y ->
                       List.range 0 (model.width - 1)
                           |> List.map
                               (\x ->
                                   getPixel x y model.level.actors
                                       |> Maybe.withDefault empty
                               )
                           |> List.append [ br [] [] ]
                   )
               |> List.concat
           )


    [ Canvas.FillStyle Color.blue
    , Canvas.FillRect
        (Canvas.Point.fromInts ( 0, 0 ))
        (Canvas.Size 20 20)
    ]

-}


view : Model -> Html Msg
view model =
    Canvas.initialize (Canvas.Size (model.width * pixelSize) (model.height * pixelSize))
        |> Canvas.batch
            (List.range 0 (model.height - 1)
                |> List.map
                    (\y ->
                        List.range 0 (model.width - 1)
                            |> List.map
                                (\x ->
                                    getPixel x y model.level.actors
                                        |> Maybe.withDefault []
                                )
                            |> List.concat
                    )
                |> List.concat
            )
        |> Canvas.toHtml []


getPixel : Int -> Int -> Dict Int Actor -> Maybe (List Canvas.DrawOp)
getPixel x y actors =
    Dict.foldr
        (\actorId actor acc ->
            (getCurrentPositionRenderComponent actor.components
                |> Maybe.andThen
                    (\renderData ->
                        getTransformComponent actor.components
                            |> Maybe.andThen
                                (\transformData ->
                                    if transformData.x == x && transformData.y == y then
                                        Just ( transformData.x, transformData.y, renderData.color )
                                    else
                                        Nothing
                                )
                    )
            )
                :: (getAdditionalPositionRenderComponent actor.components
                        |> Maybe.andThen
                            (\renderData ->
                                List.map
                                    (\{ xOffset, yOffset, color } ->
                                        getTransformComponent actor.components
                                            |> Maybe.andThen
                                                (\transformData ->
                                                    if transformData.x + xOffset == x && transformData.y + yOffset == y then
                                                        Just ( transformData.x, transformData.y, color )
                                                    else
                                                        Nothing
                                                )
                                    )
                                    renderData.positions
                                    |> Maybe.Extra.values
                                    |> List.head
                            )
                   )
                :: acc
        )
        []
        actors
        |> Maybe.Extra.values
        |> List.head
        |> Maybe.andThen
            (\( x, y, color ) ->
                Just <| asPixel x y color
            )


asPixel : Int -> Int -> Color -> List Canvas.DrawOp
asPixel x y color =
    [ Canvas.FillStyle color
    , Canvas.FillRect
        (Canvas.Point.fromInts ( x * pixelSize, y * pixelSize ))
        (Canvas.Size pixelSize pixelSize)
    ]


getTransformComponent : Dict String Component -> Maybe TransformComponentData
getTransformComponent components =
    Dict.get "transform" components
        |> Maybe.andThen
            (\component ->
                case component of
                    TransformComponent data ->
                        Just data

                    _ ->
                        Nothing
            )


getCurrentPositionRenderComponent : Dict String Component -> Maybe CurrentPositionRenderComponentData
getCurrentPositionRenderComponent components =
    Dict.get "render" components
        |> Maybe.andThen
            (\component ->
                case component of
                    CurrentPositionRenderComponent data ->
                        Just data

                    _ ->
                        Nothing
            )


getAdditionalPositionRenderComponent : Dict String Component -> Maybe AdditionalPositionsRenderComponentData
getAdditionalPositionRenderComponent components =
    Dict.get "additional-render" components
        |> Maybe.andThen
            (\component ->
                case component of
                    AdditionalPositionRenderComponent data ->
                        Just data

                    _ ->
                        Nothing
            )


addPlayer : Int -> Int -> Level -> Level
addPlayer x y level =
    let
        actors =
            Dict.insert
                level.nextActorId
                (createPlayer level.nextActorId x y)
                level.actors
    in
        { level | actors = actors, nextActorId = level.nextActorId + 1 }


createPlayer : Int -> Int -> Int -> Actor
createPlayer id x y =
    { id = id
    , components =
        Dict.fromList
            [ ( "transform", TransformComponent { x = x, y = y, movingState = NotMoving } )
            , ( "render", CurrentPositionRenderComponent { color = Color.darkGreen } )
            , ( "player-input", PlayerInputComponent )
            , ( "diamond-collector", DiamondCollectorComponent )
            , ( "can-squash", CanSquashComponent )
            , ( "rigid", RigidComponent )
            , ( "physics"
              , PhysicsComponent
                    { mass = 10
                    , shape = Square
                    , affectedByGravity = False
                    }
              )
            ]
    }


addRock : Int -> Int -> Level -> Level
addRock x y level =
    let
        actors =
            Dict.insert
                level.nextActorId
                (createRock level.nextActorId x y)
                level.actors
    in
        { level | actors = actors, nextActorId = level.nextActorId + 1 }


createRock : Int -> Int -> Int -> Actor
createRock id x y =
    { id = id
    , components =
        Dict.fromList
            [ ( "transform", TransformComponent { x = x, y = y, movingState = NotMoving } )
            , ( "render", CurrentPositionRenderComponent { color = Color.gray } )
            , ( "rigid", RigidComponent )
            , ( "physics"
              , PhysicsComponent
                    { mass = 20
                    , shape = Circle
                    , affectedByGravity = True
                    }
              )
            ]
    }


addDirt : Int -> Int -> Level -> Level
addDirt x y level =
    let
        actors =
            Dict.insert
                level.nextActorId
                (createDirt level.nextActorId x y)
                level.actors
    in
        { level | actors = actors, nextActorId = level.nextActorId + 1 }


createDirt : Int -> Int -> Int -> Actor
createDirt id x y =
    { id = id
    , components =
        Dict.fromList
            [ ( "transform", TransformComponent { x = x, y = y, movingState = NotMoving } )
            , ( "render", CurrentPositionRenderComponent { color = Color.lightBrown } )
            , ( "squashable", SquashableComponent )
            , ( "physics"
              , PhysicsComponent
                    { mass = 1
                    , shape = Square
                    , affectedByGravity = False
                    }
              )
            ]
    }


addWall : Int -> Int -> Level -> Level
addWall x y level =
    let
        actors =
            Dict.insert
                level.nextActorId
                (createWall level.nextActorId x y)
                level.actors
    in
        { level | actors = actors, nextActorId = level.nextActorId + 1 }


createWall : Int -> Int -> Int -> Actor
createWall id x y =
    { id = id
    , components =
        Dict.fromList
            [ ( "transform", TransformComponent { x = x, y = y, movingState = NotMoving } )
            , ( "render", CurrentPositionRenderComponent { color = Color.black } )
            , ( "rigid", RigidComponent )
            , ( "physics"
              , PhysicsComponent
                    { mass = 100
                    , shape = Square
                    , affectedByGravity = False
                    }
              )
            ]
    }


addDiamond : Int -> Int -> Level -> Level
addDiamond x y level =
    let
        diamonds =
            level.diamonds

        newDiamonds =
            { diamonds | total = diamonds.total + 1 }

        actors =
            Dict.insert
                level.nextActorId
                (createDiamond level.nextActorId x y)
                level.actors
    in
        { level
            | actors = actors
            , nextActorId = level.nextActorId + 1
            , diamonds = newDiamonds
        }


createDiamond : Int -> Int -> Int -> Actor
createDiamond id x y =
    { id = id
    , components =
        Dict.fromList
            [ ( "transform", TransformComponent { x = x, y = y, movingState = NotMoving } )
            , ( "render", CurrentPositionRenderComponent { color = Color.blue } )
            , ( "diamond", DiamondComponent )
            , ( "physics"
              , PhysicsComponent
                    { mass = 100
                    , shape = Square
                    , affectedByGravity = True
                    }
              )
            ]
    }


empty : Html Msg
empty =
    text "[ ]"


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Keyboard.presses KeyPressed
        , Keyboard.downs KeyDown
        , Keyboard.ups KeyUp
        , Time.every (80 * Time.millisecond) GameTick
        ]


updateKeyState : Model -> KeyStatus -> Keyboard.KeyCode -> Model
updateKeyState model status keyCode =
    let
        keys =
            model.keys
    in
        case keyCode of
            37 ->
                let
                    newKeys =
                        { keys | left = status }
                in
                    { model | keys = newKeys }

            38 ->
                let
                    newKeys =
                        { keys | up = status }
                in
                    { model | keys = newKeys }

            39 ->
                let
                    newKeys =
                        { keys | right = status }
                in
                    { model | keys = newKeys }

            40 ->
                let
                    newKeys =
                        { keys | down = status }
                in
                    { model | keys = newKeys }

            _ ->
                model
