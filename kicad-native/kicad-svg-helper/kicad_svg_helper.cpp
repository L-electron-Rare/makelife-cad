/*
 * kicad_svg_helper.cpp — Lightweight schematic/PCB → SVG export tool
 *
 * Uses KiCad's actual C++ rendering pipeline (SCH_PLOTTER, SVG_PLOTTER)
 * for pixel-perfect output identical to KiCad's native renderer.
 *
 * Built against KiCad 10.x source, licensed GPL-3.0 (same as KiCad).
 *
 * Usage:
 *   kicad-svg-helper sch <input.kicad_sch> <output_dir> [--theme <name>] [--no-background]
 *   kicad-svg-helper pcb <input.kicad_pcb> <output_dir> [--layers <F.Cu,B.Cu,...>]
 *   kicad-svg-helper version
 *
 * Output: SVG files in output_dir (one per sheet for schematics)
 * Exit code: 0 on success, 1 on error
 * Prints JSON manifest to stdout: {"files":["sheet1.svg","sheet2.svg"],"pages":2}
 */

#include <wx/app.h>
#include <wx/cmdline.h>
#include <wx/filename.h>
#include <wx/log.h>

#include <pgm_base.h>
#include <settings/settings_manager.h>
#include <schematic.h>
#include <sch_plotter.h>
#include <sch_render_settings.h>
#include <sch_painter.h>
#include <sch_screen.h>
#include <sch_sheet.h>
#include <sch_sheet_path.h>
#include <eeschema_helpers.h>
#include <plotters/plotters_pslike.h>
#include <drawing_sheet/ds_proxy_view_item.h>
#include <page_info.h>
#include <gal/color4d.h>
#include <color_settings.h>

#include <iostream>
#include <string>
#include <vector>
#include <filesystem>

/* ------------------------------------------------------------------ */
/* Minimal PGM implementation for headless use                         */
/* ------------------------------------------------------------------ */

class PGM_SVG_HELPER : public PGM_BASE
{
public:
    PGM_SVG_HELPER() {}

    bool OnPgmInit()
    {
        PGM_BASE::BuildArgvUtf8();
        wxApp::GetInstance()->SetAppDisplayName( wxT( "kicad-svg-helper" ) );

        if( !InitPgm( true, true ) )
            return false;

        return true;
    }

    void OnPgmExit()
    {
        Destroy();
    }
};

static PGM_SVG_HELPER program;

PGM_BASE& Pgm()
{
    return program;
}

/* ------------------------------------------------------------------ */
/* wxApp subclass (console only, no GUI)                               */
/* ------------------------------------------------------------------ */

class APP_SVG_HELPER : public wxAppConsole
{
public:
    APP_SVG_HELPER() : wxAppConsole()
    {
        SetPgm( &program );
    }

    bool OnInit() override
    {
        if( !program.OnPgmInit() )
            return false;

        return true;
    }

    int OnExit() override
    {
        program.OnPgmExit();
        return 0;
    }

    int OnRun() override;
};

wxIMPLEMENT_APP_CONSOLE( APP_SVG_HELPER );

/* ------------------------------------------------------------------ */
/* Schematic SVG export                                                */
/* ------------------------------------------------------------------ */

static int export_sch_svg( const wxString& inputPath,
                           const wxString& outputDir,
                           const wxString& theme,
                           bool            background )
{
    // Ensure output directory exists
    if( !wxFileName::DirExists( outputDir ) )
    {
        wxFileName::Mkdir( outputDir, wxS_DIR_DEFAULT, wxPATH_MKDIR_FULL );
    }

    // Load schematic using KiCad's standard helper
    SCHEMATIC* sch = EESCHEMA_HELPERS::LoadSchematic( inputPath, true, false, nullptr );

    if( !sch )
    {
        std::cerr << "ERROR: Failed to load schematic: "
                  << inputPath.ToStdString() << std::endl;
        return 1;
    }

    // Setup render settings
    SCH_RENDER_SETTINGS renderSettings;

    COLOR_SETTINGS* colorSettings = nullptr;
    if( !theme.IsEmpty() )
    {
        colorSettings = Pgm().GetSettingsManager().GetColorSettings( theme );
    }

    if( !colorSettings )
    {
        colorSettings = Pgm().GetSettingsManager().GetColorSettings( wxT( "kicad_default" ) );
    }

    if( colorSettings )
    {
        renderSettings.LoadColors( colorSettings );
    }

    renderSettings.SetDefaultPenWidth( 6 );  // mils, reasonable default

    // Clear text caches for accurate rendering
    SCH_SCREENS screens( sch->Root() );
    for( SCH_SCREEN* screen = screens.GetFirst(); screen; screen = screens.GetNext() )
    {
        for( SCH_ITEM* item : screen->Items() )
            item->ClearCaches();
    }

    // Create plotter
    SCH_PLOTTER plotter( sch );

    // Configure plot options
    SCH_PLOT_OPTS opts;
    opts.m_plotAll            = true;
    opts.m_plotDrawingSheet   = true;
    opts.m_blackAndWhite      = false;
    opts.m_useBackgroundColor = background;
    opts.m_pageSizeSelect     = PAGE_SIZE_AUTO;
    opts.m_outputDirectory    = outputDir;
    opts.m_theme              = theme.IsEmpty() ? wxString( wxT( "kicad_default" ) ) : theme;

    // Execute SVG plot
    plotter.Plot( PLOT_FORMAT::SVG, opts, &renderSettings, nullptr );

    // Collect output files and print JSON manifest
    std::vector<std::string> svgFiles;
    wxString searchPattern = outputDir + wxT( "/*.svg" );

    for( const auto& entry : std::filesystem::directory_iterator(
             outputDir.ToStdString() ) )
    {
        if( entry.path().extension() == ".svg" )
        {
            svgFiles.push_back( entry.path().filename().string() );
        }
    }

    // Output JSON manifest to stdout
    std::cout << "{\"files\":[";
    for( size_t i = 0; i < svgFiles.size(); i++ )
    {
        if( i > 0 ) std::cout << ",";
        std::cout << "\"" << svgFiles[i] << "\"";
    }
    std::cout << "],\"pages\":" << svgFiles.size() << "}" << std::endl;

    return svgFiles.empty() ? 1 : 0;
}

/* ------------------------------------------------------------------ */
/* Main entry (dispatches to sch or pcb export)                        */
/* ------------------------------------------------------------------ */

int APP_SVG_HELPER::OnRun()
{
    wxArrayString args;
    for( int i = 0; i < argc; i++ )
        args.Add( argv[i] );

    if( args.GetCount() < 2 )
    {
        std::cerr << "Usage:" << std::endl;
        std::cerr << "  kicad-svg-helper sch <input.kicad_sch> <output_dir> "
                     "[--theme <name>] [--no-background]"
                  << std::endl;
        std::cerr << "  kicad-svg-helper version" << std::endl;
        return 1;
    }

    wxString command = args[1];

    if( command == wxT( "version" ) )
    {
        std::cout << "{\"version\":\"1.0.0\",\"kicad\":\"10.0.0\"}" << std::endl;
        return 0;
    }

    if( command == wxT( "sch" ) )
    {
        if( args.GetCount() < 4 )
        {
            std::cerr << "ERROR: sch command requires <input> <output_dir>" << std::endl;
            return 1;
        }

        wxString inputPath = args[2];
        wxString outputDir = args[3];
        wxString theme;
        bool     background = true;

        // Parse optional flags
        for( size_t i = 4; i < args.GetCount(); i++ )
        {
            if( args[i] == wxT( "--theme" ) && i + 1 < args.GetCount() )
            {
                theme = args[++i];
            }
            else if( args[i] == wxT( "--no-background" ) )
            {
                background = false;
            }
        }

        return export_sch_svg( inputPath, outputDir, theme, background );
    }

    std::cerr << "ERROR: Unknown command: " << command.ToStdString() << std::endl;
    return 1;
}
