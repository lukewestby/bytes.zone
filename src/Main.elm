module Main exposing (main)

import Browser.Dom
import Browser.Events
import Colors
import Css
import Css.Global
import Css.Reset as Reset
import Date
import Elements
import Feed
import Firework exposing (Firework)
import Head
import Head.Seo as Seo
import HomePage
import Html as Unstyled
import Html.Styled as Html exposing (Html)
import Html.Styled.Attributes as Attr exposing (css)
import Index
import Json.Decode
import Markdown.Parser
import Metadata exposing (Metadata)
import ModularScale
import Pages exposing (images, pages)
import Pages.Directory as Directory exposing (Directory)
import Pages.Document
import Pages.ImagePath as ImagePath exposing (ImagePath)
import Pages.Manifest as Manifest
import Pages.Manifest.Category
import Pages.PagePath as PagePath exposing (PagePath)
import Pages.Platform exposing (Page)
import Pages.StaticHttp as StaticHttp
import Particle.System exposing (System)
import Process
import Random
import Random.Extra
import Random.Float exposing (normal)
import Svg.Attributes as SAttr
import Task
import Time


manifest : Manifest.Config Pages.PathKey
manifest =
    { backgroundColor = Just Colors.white
    , categories =
        [ Pages.Manifest.Category.education
        , Pages.Manifest.Category.productivity
        ]
    , displayMode = Manifest.Standalone
    , orientation = Manifest.Portrait
    , description = "get in the bytes zone"
    , iarcRatingId = Nothing
    , name = "bytes.zone"
    , themeColor = Just Colors.greenMid
    , startUrl = pages.index
    , shortName = Just "bytes.zone"
    , sourceIcon = images.icon
    }


type alias Rendered =
    Html Msg


main : Pages.Platform.Program Model Msg Metadata Rendered
main =
    Pages.Platform.application
        { init = init
        , view = view
        , update = update
        , subscriptions = subscriptions
        , documents = [ markdownDocument ]
        , manifest = manifest
        , canonicalSiteUrl = canonicalSiteUrl
        , onPageChange = ChangePath
        , generateFiles = generateFiles
        , internals = Pages.internals
        }


generateFiles :
    List
        { path : PagePath Pages.PathKey
        , frontmatter : Metadata
        , body : String
        }
    ->
        List
            (Result String
                { path : List String
                , content : String
                }
            )
generateFiles pages =
    [ pages
        |> Feed.generate
            { title = "bytes.zone"
            , tagline = siteTagline
            , url = [ "posts", "index.xml" ]
            , siteUrl = canonicalSiteUrl
            }
        |> Ok
    ]


markdownDocument : ( String, Pages.Document.DocumentHandler Metadata Rendered )
markdownDocument =
    Pages.Document.parser
        { extension = "md"
        , metadata = Metadata.decoder
        , body =
            Markdown.Parser.parse
                >> Result.mapError (List.map Markdown.Parser.deadEndToString >> String.join "\n\n")
                >> Result.andThen (Markdown.Parser.render Elements.renderer)
                >> Result.map (Html.section [])
        }


type alias Model =
    { path : Maybe Location
    , particles : System Firework
    , seed : Random.Seed
    , viewportWidth : Float
    }


type alias Location =
    { path : PagePath Pages.PathKey
    , query : Maybe String
    , fragment : Maybe String
    }


init : Maybe Location -> ( Model, Cmd Msg )
init path =
    ( { path = path
      , particles = Particle.System.init (Random.initialSeed 0)
      , seed = Random.initialSeed (Time.posixToMillis Pages.builtAt)
      , viewportWidth = 0
      }
    , Task.perform
        (\viewport -> WidthChanged viewport.scene.width)
        Browser.Dom.getViewport
    )


type Msg
    = ParticleBurst
    | ParticleBurstOffset
    | ParticleMsg (Particle.System.Msg Firework)
    | ChangePath Location
    | WidthChanged Float


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        ParticleBurst ->
            let
                ( offset, newSeed ) =
                    Random.step (normal 1000 250) model.seed
            in
            ( { model | seed = newSeed }
            , Process.sleep offset |> Task.perform (\_ -> ParticleBurstOffset)
            )

        ParticleBurstOffset ->
            ( { model
                | particles =
                    Particle.System.burst
                        (Random.Extra.andThen2 Firework.at
                            (normal 300 100)
                            (normal 300 100)
                        )
                        model.particles
              }
            , Cmd.none
            )

        ParticleMsg subMsg ->
            -- this is a pretty hot path and it's faster to reconstruct a
            -- whole record than update a field for whatever reason.
            ( { path = model.path
              , particles = Particle.System.update subMsg model.particles
              , seed = model.seed
              , viewportWidth = model.viewportWidth
              }
            , Cmd.none
            )

        ChangePath newPath ->
            ( { model | path = Just newPath }
            , Cmd.none
            )

        WidthChanged width ->
            ( { model | viewportWidth = width }
            , Cmd.none
            )


subscriptions : Model -> Sub Msg
subscriptions model =
    let
        particleSubs =
            if shouldDoFireworks model then
                Sub.batch
                    [ Particle.System.sub [] ParticleMsg model.particles
                    , Time.every 1000 (\_ -> ParticleBurst)
                    ]

            else
                Sub.none
    in
    Sub.batch
        [ particleSubs
        , Browser.Events.onResize (\width _ -> WidthChanged (toFloat width))
        ]


shouldDoFireworks : Model -> Bool
shouldDoFireworks { path, viewportWidth } =
    let
        acceptableWidth =
            ModularScale.scalePx 7.5
                -- margin
                + ModularScale.scalePx 2
                -- just to have a nice viewport
                + 500
    in
    Maybe.map .path path == Just Pages.pages.index && viewportWidth > acceptableWidth


view :
    List ( PagePath Pages.PathKey, Metadata )
    ->
        { path : PagePath Pages.PathKey
        , frontmatter : Metadata
        }
    ->
        StaticHttp.Request
            { view : Model -> Rendered -> { title : String, body : Unstyled.Html Msg }
            , head : List (Head.Tag Pages.PathKey)
            }
view siteMetadata page =
    StaticHttp.succeed
        { view =
            \model viewForPage ->
                let
                    { title, body } =
                        pageView model siteMetadata page viewForPage
                in
                { title = title
                , body = Html.toUnstyled body
                }
        , head = head page.frontmatter
        }


pageView :
    Model
    -> List ( PagePath Pages.PathKey, Metadata )
    -> { path : PagePath Pages.PathKey, frontmatter : Metadata }
    -> Rendered
    -> { title : String, body : Html Msg }
pageView model siteMetadata page viewForPage =
    case page.frontmatter of
        Metadata.HomePage metadata ->
            { title = metadata.title
            , body = pageFrame model page.path <| HomePage.view siteMetadata metadata viewForPage
            }

        Metadata.Page metadata ->
            { title = metadata.title
            , body = pageFrame model page.path [ Html.text "TODO: PAGE!" ]
            }

        Metadata.Post metadata ->
            { title = metadata.title
            , body =
                pageFrame model
                    page.path
                    [ Elements.h1 [] [ Html.text metadata.title ]
                    , Elements.p 0
                        [ css [ Css.fontStyle Css.italic ] ]
                        [ Elements.publishedAt metadata.publishedAt ]
                    , viewForPage
                    ]
            }

        Metadata.Talk metadata ->
            { title = metadata.title
            , body =
                pageFrame model
                    page.path
                    [ Elements.h1 [] [ Html.text metadata.title ]
                    , viewForPage
                    ]
            }

        Metadata.Index category ->
            { title = Metadata.categoryTitle category
            , body = pageFrame model page.path [ Index.view siteMetadata category ]
            }


pageFrame : Model -> PagePath Pages.PathKey -> List (Html msg) -> Html msg
pageFrame model path stuff =
    let
        fontFace : String -> List ( String, String ) -> String -> Int -> Html msg
        fontFace name paths style weight =
            String.concat
                [ "@font-face {"
                , "font-family:'"
                , name
                , "';font-style:"
                , style
                , ";font-weight:"
                , String.fromInt weight
                , ";font-display:swap;src:local('"
                , name
                , "'),"
                , paths
                    |> List.map (\( pathToFont, format ) -> "url(" ++ pathToFont ++ ") format('" ++ format ++ "')")
                    |> String.join ","
                , ";}"
                ]
                |> Html.text
    in
    Html.div
        []
        [ Reset.meyerV2
        , Reset.borderBoxV201408
        , Css.Global.global
            [ Css.Global.body [ Css.backgroundColor (Colors.toCss Colors.white) ]
            , Css.Global.html [ Css.fontSize (Css.px ModularScale.baseFontSize) ]
            ]
        , Html.node "style"
            []
            [ fontFace "Exo 2" [ ( "/fonts/Exo2-Bold.woff2", "woff2" ) ] "normal" 700
            , fontFace "Exo 2" [ ( "/fonts/Exo2-BoldItalic.woff2", "woff2" ) ] "italic" 700
            , fontFace "Exo 2" [ ( "/fonts/Exo2-Regular.woff2", "woff2" ) ] "normal" 400
            , fontFace "Jetbrains Mono" [ ( "/fonts/Jetbrains-Mono.woff2", "woff2" ) ] "normal" 400
            , fontFace "Open Sans" [ ( "/fonts/OpenSans-Bold.woff2", "woff2" ) ] "normal" 700
            , fontFace "Open Sans" [ ( "/fonts/OpenSans-BoldItalic.woff2", "woff2" ) ] "italic" 700
            , fontFace "Open Sans" [ ( "/fonts/OpenSans-Italic.woff2", "woff2" ) ] "italic" 400
            , fontFace "Open Sans" [ ( "/fonts/OpenSans.woff2", "woff2" ) ] "normal" 400
            ]
        , pageHeader path
        , Html.main_ [] stuff
        , if shouldDoFireworks model then
            Html.fromUnstyled <|
                Particle.System.view Firework.view
                    [ let
                        offset =
                            (ModularScale.scale 7.5 + ModularScale.scale 2)
                                |> String.fromFloat
                      in
                      SAttr.style
                        ("position: absolute; top: 0; left: "
                            ++ offset
                            ++ "rem; width: calc(100% - "
                            ++ offset
                            ++ "rem); height: 100vh"
                        )
                    ]
                    model.particles

          else
            Html.text ""
        , pageFooter
        ]


pageHeader : PagePath Pages.PathKey -> Html msg
pageHeader path =
    Html.header
        [ css
            [ Css.marginTop (ModularScale.rem 2)
            , Css.displayFlex
            ]
        ]
        [ Elements.pageTitle
            [ Attr.href (PagePath.toString pages.index) ]
            [ Html.text "bytes.zone" ]
        , let
            navLinkStyle =
                css
                    [ Elements.exo2
                    , Css.marginLeft (ModularScale.rem 1)
                    ]
          in
          Html.ul
            [ css [ Css.displayFlex ]
            ]
            [ Html.li [ navLinkStyle ] [ headerLink "posts" pages.posts.directory path ]
            , Html.li [ navLinkStyle ] [ headerLink "talks" pages.talks.directory path ]
            ]
        ]


headerLink : String -> Directory Pages.PathKey Directory.WithIndex -> PagePath Pages.PathKey -> Html msg
headerLink caption directory currentPath =
    let
        tag =
            if Directory.includes directory currentPath then
                Elements.a

            else
                Elements.inactiveHeaderLink
    in
    tag
        [ Attr.href <| PagePath.toString <| Directory.indexPath directory ]
        [ Html.text caption ]


pageFooter : Html msg
pageFooter =
    Html.footer []
        [ Elements.hr
        , Elements.p 0
            [ css [ Css.marginBottom (ModularScale.rem 2) ] ]
            [ Html.text "The content on this site is released under the "
            , Elements.a [ Attr.href "https://creativecommons.org/licenses/by/4.0/" ] [ Html.text "Creative Commons Attribution 4.0 International license" ]
            , Html.text "."
            ]
        ]


{-| <https://developer.twitter.com/en/docs/tweets/optimize-with-cards/overview/abouts-cards>
<https://htmlhead.dev>
<https://html.spec.whatwg.org/multipage/semantics.html#standard-metadata-names>
<https://ogp.me/>
-}
head : Metadata -> List (Head.Tag Pages.PathKey)
head metadata =
    case metadata of
        Metadata.HomePage meta ->
            Seo.summaryLarge
                { canonicalUrlOverride = Nothing
                , siteName = "bytes.zone"
                , image =
                    { url = images.icon
                    , alt = "bytes.zone logo"
                    , dimensions = Nothing
                    , mimeType = Nothing
                    }
                , description = siteTagline
                , locale = Nothing
                , title = meta.title
                }
                |> Seo.website

        Metadata.Page meta ->
            Seo.summaryLarge
                { canonicalUrlOverride = Nothing
                , siteName = "bytes.zone"
                , image =
                    { url = images.icon
                    , alt = "bytes.zone logo"
                    , dimensions = Nothing
                    , mimeType = Nothing
                    }
                , description = Maybe.withDefault siteTagline meta.summary
                , locale = Nothing
                , title = meta.title
                }
                |> Seo.website

        Metadata.Post meta ->
            Seo.summaryLarge
                { canonicalUrlOverride = Nothing
                , siteName = "bytes.zone"
                , image =
                    { url = images.icon
                    , alt = "bytes.zone logo"
                    , dimensions = Nothing
                    , mimeType = Nothing
                    }
                , description = Maybe.withDefault siteTagline meta.summary
                , locale = Nothing
                , title = meta.title
                }
                |> Seo.article
                    { tags = []
                    , section = Nothing
                    , publishedTime = Nothing
                    , modifiedTime = Nothing
                    , expirationTime = Nothing
                    }

        Metadata.Talk meta ->
            Seo.summaryLarge
                { canonicalUrlOverride = Nothing
                , siteName = "bytes.zone"
                , image =
                    { url = images.icon
                    , alt = "bytes.zone logo"
                    , dimensions = Nothing
                    , mimeType = Nothing
                    }
                , description = siteTagline
                , locale = Nothing
                , title = meta.title
                }
                |> Seo.article
                    { tags = []
                    , section = Nothing
                    , publishedTime = Nothing
                    , modifiedTime = Nothing
                    , expirationTime = Nothing
                    }

        Metadata.Index category ->
            Seo.summary
                { canonicalUrlOverride = Nothing
                , siteName = "bytes.zone"
                , image =
                    { url = images.icon
                    , alt = "bytes.zone logo"
                    , dimensions = Nothing
                    , mimeType = Nothing
                    }
                , description = siteTagline
                , locale = Nothing
                , title = Metadata.categoryTitle category
                }
                |> Seo.website


canonicalSiteUrl : String
canonicalSiteUrl =
    "https://bytes.zone"


siteTagline : String
siteTagline =
    "get in the bytes zone"


publishedDateView metadata =
    Html.text
        (metadata.published
            |> Date.format "MMMM ddd, yyyy"
        )
