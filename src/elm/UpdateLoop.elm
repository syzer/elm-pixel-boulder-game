module UpdateLoop exposing (update)

import Actor.Actor as Actor exposing (Level)
import Dict exposing (Dict)
import InputController
import Data.Common exposing (Position, Direction)


updateBorder : Int
updateBorder =
    5


update : Maybe Direction -> Level -> Level
update maybeDirection level =
    List.foldr
        (\y level ->
            List.foldr
                (\x level ->
                    Actor.getActorIdsByXY x y level
                        |> List.foldr
                            (\actorId level ->
                                Actor.getActorById actorId level
                                    |> Maybe.andThen
                                        (\actor ->
                                            Dict.foldr
                                                (\_ component level ->
                                                    Actor.getActorById actorId level
                                                        |> Maybe.andThen
                                                            (\actor ->
                                                                let
                                                                    updatedLevel =
                                                                        case component of
                                                                            Actor.PlayerInputComponent ->
                                                                                Actor.updatePlayerInputComponent maybeDirection actor level

                                                                            Actor.DiamondCollectorComponent ->
                                                                                Actor.updateDiamondCollectorComponent actor level

                                                                            CanSquashComponent ->
                                                                                trySquashingThings level actor

                                                                            PhysicsComponent physics ->
                                                                                tryApplyPhysics currentTick level actor physics

                                                                            AIComponent ai ->
                                                                                tryApplyAI currentTick level actor ai

                                                                            CameraComponent camera ->
                                                                                tryMoveCamera level actor camera

                                                                            DownSmashComponent downSmash ->
                                                                                tryDownSmash level actor downSmash

                                                                            DamageComponent damageData ->
                                                                                handleDamageComponent actor damageData level

                                                                            _ ->
                                                                                level
                                                                in
                                                                    Just updatedLevel
                                                            )
                                                        |> Maybe.withDefault level
                                                )
                                                level
                                                actor.components
                                                |> Just
                                        )
                                    |> Maybe.withDefault level
                            )
                            level
                )
                level
                (List.range (view.position.x - updateBorder) (view.position.x + view.width + updateBorder))
        )
        model.level
        (List.range (view.position.y - updateBorder) (view.position.y + view.height + updateBorder))
