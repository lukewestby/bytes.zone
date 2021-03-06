module Metadata exposing (HomePageMetadata, IndexCategory(..), Metadata(..), PageMetadata, categoryTitle, decoder, publishedAt, summary, title)

import Date exposing (Date)
import Dict exposing (Dict)
import Iso8601
import Json.Decode as Decode exposing (Decoder)
import List.Extra
import Pages
import Pages.ImagePath as ImagePath exposing (ImagePath)
import Time


type Metadata
    = Page PageMetadata
    | HomePage HomePageMetadata
    | Post PostMetadata
    | Talk TalkMetadata
    | Index IndexCategory


type IndexCategory
    = Posts
    | Talks


type alias HomePageMetadata =
    { title : String }


type alias PageMetadata =
    { title : String
    , summary : Maybe String
    , publishedAt : Time.Posix
    }


type alias PostMetadata =
    PageMetadata


type alias TalkMetadata =
    { title : String
    , event : String
    , publishedAt : Time.Posix
    }


decoder =
    Decode.field "type" Decode.string
        |> Decode.andThen
            (\pageType ->
                case pageType of
                    "page" ->
                        Decode.map3
                            (\title_ publishedAt_ summary_ ->
                                Page
                                    { title = title_
                                    , publishedAt = publishedAt_
                                    , summary = summary_
                                    }
                            )
                            (Decode.field "title" Decode.string)
                            (Decode.field "updated" Iso8601.decoder)
                            (Decode.maybe (Decode.field "summary" Decode.string))

                    "homepage" ->
                        Decode.field "title" Decode.string
                            |> Decode.map (\title_ -> HomePage { title = title_ })

                    "post" ->
                        Decode.map3
                            (\title_ publishedAt_ summary_ ->
                                Post
                                    { title = title_
                                    , publishedAt = publishedAt_
                                    , summary = summary_
                                    }
                            )
                            (Decode.field "title" Decode.string)
                            (Decode.field "published" Iso8601.decoder)
                            (Decode.maybe (Decode.field "summary" Decode.string))

                    "talk" ->
                        Decode.map3
                            (\title_ event publishedAt_ ->
                                Talk
                                    { title = title_
                                    , event = event
                                    , publishedAt = publishedAt_
                                    }
                            )
                            (Decode.field "title" Decode.string)
                            (Decode.field "event" Decode.string)
                            (Decode.field "published" Iso8601.decoder)

                    "index" ->
                        Decode.field "category" Decode.string
                            |> Decode.andThen
                                (\category ->
                                    case category of
                                        "posts" ->
                                            Decode.succeed Posts

                                        "talks" ->
                                            Decode.succeed Talks

                                        _ ->
                                            Decode.fail ("Unexpected index category " ++ category)
                                )
                            |> Decode.map Index

                    _ ->
                        Decode.fail ("Unexpected page type " ++ pageType)
            )


title : Metadata -> String
title metadata =
    case metadata of
        Talk pageMeta ->
            pageMeta.title

        Page pageMeta ->
            pageMeta.title

        Post pageMeta ->
            pageMeta.title

        HomePage pageMeta ->
            pageMeta.title

        Index category ->
            categoryTitle category


categoryTitle : IndexCategory -> String
categoryTitle category =
    case category of
        Posts ->
            "Posts"

        Talks ->
            "Talks"


publishedAt : Metadata -> Time.Posix
publishedAt metadata =
    case metadata of
        Talk pageMeta ->
            pageMeta.publishedAt

        Page pageMeta ->
            pageMeta.publishedAt

        Post pageMeta ->
            pageMeta.publishedAt

        HomePage pageMeta ->
            Time.millisToPosix 0

        Index category ->
            Time.millisToPosix 0


summary : Metadata -> Maybe String
summary metadata =
    case metadata of
        Talk _ ->
            Nothing

        Page pageMeta ->
            pageMeta.summary

        Post pageMeta ->
            pageMeta.summary

        HomePage _ ->
            Nothing

        Index _ ->
            Nothing
